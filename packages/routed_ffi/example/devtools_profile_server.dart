import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:server_native/server_native.dart';
import 'package:server_native/src/bridge/bridge_runtime.dart';

const _jsonHeaders = <MapEntry<String, String>>[
  MapEntry(HttpHeaders.contentTypeHeader, 'application/json'),
];

const _textHeaders = <MapEntry<String, String>>[
  MapEntry(HttpHeaders.contentTypeHeader, 'text/plain; charset=utf-8'),
];

/// Runnable profile target for Dart DevTools.
///
/// Run:
///   dart --observe example/devtools_profile_server.dart --mode=direct --port=8080
/// Then open DevTools and drive load against:
///   GET  /health
///   GET  /cpu?iterations=800000&seed=7
///   POST /upload
///   POST /echo
Future<void> main(List<String> args) async {
  final config = _ProfileConfig.parse(args);
  stdout.writeln(
    '[devtools] mode=${config.mode} host=${config.host} '
    'port=${config.port} http3=${config.http3}',
  );
  stdout.writeln('[devtools] endpoints: /health, /cpu, /upload, /echo');

  if (config.mode == 'http') {
    await serveFfiHttp(
      _httpHandler,
      host: config.host,
      port: config.port,
      echo: true,
      http3: config.http3,
    );
    return;
  }

  await serveFfiDirect(
    _directHandler,
    host: config.host,
    port: config.port,
    echo: true,
    http3: config.http3,
  );
}

Future<FfiDirectResponse> _directHandler(FfiDirectRequest request) async {
  if (request.path == '/health') {
    return FfiDirectResponse.bytes(
      headers: _jsonHeaders,
      bodyBytes: Uint8List.fromList(utf8.encode('{"ok":true}')),
    );
  }

  if (request.path == '/cpu') {
    final iterations = _boundedIterations(
      request.uri.queryParameters['iterations'],
    );
    final seed = int.tryParse(request.uri.queryParameters['seed'] ?? '') ?? 1;
    final checksum = _cpuBurn(iterations: iterations, seed: seed);
    final payload =
        '{"iterations":$iterations,"seed":$seed,"checksum":$checksum}';
    return FfiDirectResponse.bytes(
      headers: _jsonHeaders,
      bodyBytes: Uint8List.fromList(utf8.encode(payload)),
    );
  }

  if (request.path == '/echo' && request.method == 'POST') {
    final bodyBytes = await _collectBytes(request.body);
    final payload =
        '{"ok":true,"bytes":${bodyBytes.length},"preview":"${_preview(bodyBytes)}"}';
    return FfiDirectResponse.bytes(
      headers: _jsonHeaders,
      bodyBytes: Uint8List.fromList(utf8.encode(payload)),
    );
  }

  if (request.path == '/upload' && request.method == 'POST') {
    final stats = await _collectBodyStats(request.body);
    final payload =
        '{"ok":true,"bytes":${stats.bytes},"preview":"${stats.previewBase64}"}';
    return FfiDirectResponse.bytes(
      headers: _jsonHeaders,
      bodyBytes: Uint8List.fromList(utf8.encode(payload)),
    );
  }

  return FfiDirectResponse.bytes(
    status: HttpStatus.notFound,
    headers: _textHeaders,
    bodyBytes: Uint8List.fromList(utf8.encode('Not Found')),
  );
}

Future<void> _httpHandler(BridgeHttpRequest request) async {
  final response = request.response;

  if (request.uri.path == '/health') {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write('{"ok":true}');
    await response.close();
    return;
  }

  if (request.uri.path == '/cpu') {
    final iterations = _boundedIterations(
      request.uri.queryParameters['iterations'],
    );
    final seed = int.tryParse(request.uri.queryParameters['seed'] ?? '') ?? 1;
    final checksum = _cpuBurn(iterations: iterations, seed: seed);
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write(
      '{"iterations":$iterations,"seed":$seed,"checksum":$checksum}',
    );
    await response.close();
    return;
  }

  if (request.uri.path == '/echo' && request.method == 'POST') {
    final bodyBytes = await _collectBytes(request);
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write(
      '{"ok":true,"bytes":${bodyBytes.length},"preview":"${_preview(bodyBytes)}"}',
    );
    await response.close();
    return;
  }

  if (request.uri.path == '/upload' && request.method == 'POST') {
    final stats = await _collectBodyStats(request);
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write(
      '{"ok":true,"bytes":${stats.bytes},"preview":"${stats.previewBase64}"}',
    );
    await response.close();
    return;
  }

  response.statusCode = HttpStatus.notFound;
  response.headers.contentType = ContentType.text;
  response.write('Not Found');
  await response.close();
}

Future<Uint8List> _collectBytes(Stream<Uint8List> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (chunk.isNotEmpty) {
      builder.add(chunk);
    }
  }
  return builder.takeBytes();
}

Future<_BodyStats> _collectBodyStats(Stream<Uint8List> stream) async {
  var total = 0;
  final preview = Uint8List(64);
  var previewLength = 0;
  await for (final chunk in stream) {
    if (chunk.isEmpty) {
      continue;
    }
    total += chunk.length;
    if (previewLength < preview.length) {
      final remaining = preview.length - previewLength;
      final take = chunk.length < remaining ? chunk.length : remaining;
      preview.setRange(previewLength, previewLength + take, chunk);
      previewLength += take;
    }
  }
  final previewBytes = previewLength == preview.length
      ? preview
      : Uint8List.sublistView(preview, 0, previewLength);
  return _BodyStats(
    bytes: total,
    previewBase64: previewLength == 0 ? '' : base64Url.encode(previewBytes),
  );
}

int _cpuBurn({required int iterations, required int seed}) {
  var x = seed ^ 0x9e3779b9;
  for (var i = 0; i < iterations; i++) {
    x ^= (x << 13);
    x ^= (x >>> 17);
    x ^= (x << 5);
    x = (x + i) & 0x7fffffff;
  }
  return x;
}

int _boundedIterations(String? raw) {
  final parsed = int.tryParse(raw ?? '');
  if (parsed == null) {
    return 800000;
  }
  if (parsed < 1) {
    return 1;
  }
  if (parsed > 50000000) {
    return 50000000;
  }
  return parsed;
}

String _preview(Uint8List bytes) {
  if (bytes.isEmpty) {
    return '';
  }
  final sample = bytes.length <= 64
      ? bytes
      : Uint8List.sublistView(bytes, 0, 64);
  return base64Url.encode(sample);
}

final class _BodyStats {
  const _BodyStats({required this.bytes, required this.previewBase64});

  final int bytes;
  final String previewBase64;
}

final class _ProfileConfig {
  const _ProfileConfig({
    required this.mode,
    required this.host,
    required this.port,
    required this.http3,
  });

  final String mode;
  final String host;
  final int port;
  final bool http3;

  static _ProfileConfig parse(List<String> args) {
    var mode = 'direct';
    var host = '127.0.0.1';
    var port = 8080;
    var http3 = false;

    for (final arg in args) {
      if (arg == '--help' || arg == '-h') {
        _printUsage();
        exit(0);
      }
      if (arg.startsWith('--mode=')) {
        mode = arg.substring('--mode='.length).trim();
        continue;
      }
      if (arg.startsWith('--host=')) {
        host = arg.substring('--host='.length).trim();
        continue;
      }
      if (arg.startsWith('--port=')) {
        port = int.parse(arg.substring('--port='.length).trim());
        continue;
      }
      if (arg == '--http3') {
        http3 = true;
        continue;
      }
      stderr.writeln('Unknown argument: $arg');
      _printUsage();
      exit(64);
    }

    if (mode != 'direct' && mode != 'http') {
      stderr.writeln('Invalid --mode value: $mode (expected: direct|http)');
      _printUsage();
      exit(64);
    }
    if (port <= 0 || port > 65535) {
      stderr.writeln('Invalid --port value: $port');
      _printUsage();
      exit(64);
    }

    return _ProfileConfig(mode: mode, host: host, port: port, http3: http3);
  }

  static void _printUsage() {
    stdout.writeln(
      'Usage: dart --observe example/devtools_profile_server.dart [options]',
    );
    stdout.writeln('Options:');
    stdout.writeln('  --mode=direct|http   Transport mode (default: direct)');
    stdout.writeln('  --host=ADDR          Bind host (default: 127.0.0.1)');
    stdout.writeln('  --port=N             Bind port (default: 8080)');
    stdout.writeln(
      '  --http3              Enable HTTP/3 (TLS mode only; off by default)',
    );
  }
}
