import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:relic/io_adapter.dart';
import 'package:relic/relic.dart' as relic;
import 'package:routed/routed.dart';
import 'package:server_native/server_native.dart';
import 'package:server_native/src/native/server_native_transport.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;

final class _BenchmarkOptions {
  const _BenchmarkOptions({
    required this.requests,
    required this.concurrency,
    required this.warmup,
    required this.iterations,
    required this.framework,
    required this.nativeCallback,
    required this.jsonOutput,
  });

  final int requests;
  final int concurrency;
  final int warmup;
  final int iterations;
  final String framework;
  final bool nativeCallback;
  final bool jsonOutput;
}

final class _RunResult {
  const _RunResult({
    required this.requests,
    required this.totalMicros,
    required this.requestsPerSecond,
    required this.p50Micros,
    required this.p95Micros,
  });

  final int requests;
  final int totalMicros;
  final double requestsPerSecond;
  final int p50Micros;
  final int p95Micros;

  Map<String, Object> toJson() => <String, Object>{
    'requests': requests,
    'totalMicros': totalMicros,
    'requestsPerSecond': requestsPerSecond,
    'p50Micros': p50Micros,
    'p95Micros': p95Micros,
  };
}

final class _CaseSummary {
  const _CaseSummary({
    required this.label,
    required this.requestsPerSecond,
    required this.p50Micros,
    required this.p95Micros,
    required this.totalMicros,
    required this.requests,
  });

  final String label;
  final double requestsPerSecond;
  final int p50Micros;
  final int p95Micros;
  final int totalMicros;
  final int requests;

  Map<String, Object> toJson() => <String, Object>{
    'label': label,
    'requestsPerSecond': requestsPerSecond,
    'p50Micros': p50Micros,
    'p95Micros': p95Micros,
    'totalMicros': totalMicros,
    'requests': requests,
  };
}

final class _RunningServer {
  _RunningServer({
    required this.baseUri,
    required this.close,
    this.targetPath = '/health',
  });

  final Uri baseUri;
  final Future<void> Function() close;
  final String targetPath;
}

typedef _ServerFactory = Future<_RunningServer> Function();

void main(List<String> args) async {
  final options = _parseArgs(args);
  final cases = _buildCases(options);
  if (cases.isEmpty) {
    stderr.writeln(
      'No benchmark cases selected. Use --framework=all|dart_io|routed|relic|shelf|native_direct.',
    );
    exitCode = 2;
    return;
  }

  stdout.writeln(
    'Benchmark options: requests=${options.requests}, concurrency=${options.concurrency}, '
    'warmup=${options.warmup}, iterations=${options.iterations}, '
    'framework=${options.framework}, nativeCallback=${options.nativeCallback}',
  );

  final summaries = <_CaseSummary>[];
  for (final benchmarkCase in cases.entries) {
    final label = benchmarkCase.key;
    final factory = benchmarkCase.value;
    stdout.writeln('\nCase: $label');
    final running = await factory();
    try {
      await _waitUntilUp(running.baseUri.replace(path: running.targetPath));

      if (options.warmup > 0) {
        await _runLoad(
          baseUri: running.baseUri,
          targetPath: running.targetPath,
          requests: options.warmup,
          concurrency: options.concurrency,
        );
      }

      final runs = <_RunResult>[];
      for (var i = 0; i < options.iterations; i++) {
        stdout.writeln('  Iteration ${i + 1}/${options.iterations}');
        final run = await _runLoad(
          baseUri: running.baseUri,
          targetPath: running.targetPath,
          requests: options.requests,
          concurrency: options.concurrency,
        );
        runs.add(run);
      }

      final summary = _summarize(label, runs);
      summaries.add(summary);
      stdout.writeln(
        '  ${summary.label}: ${summary.requestsPerSecond.toStringAsFixed(0)} req/s, '
        'p95=${(summary.p95Micros / 1000).toStringAsFixed(2)} ms',
      );
    } finally {
      await running.close();
    }
  }

  summaries.sort((a, b) => b.requestsPerSecond.compareTo(a.requestsPerSecond));

  stdout.writeln('\nResults');
  stdout.writeln(
    'transport                req/s      p50(us)   p95(us)   total(ms)   requests',
  );
  for (final summary in summaries) {
    final label = summary.label.padRight(24);
    final reqPerSec = summary.requestsPerSecond.toStringAsFixed(0).padLeft(8);
    final p50 = summary.p50Micros.toString().padLeft(8);
    final p95 = summary.p95Micros.toString().padLeft(8);
    final totalMs = (summary.totalMicros / 1000).toStringAsFixed(2).padLeft(10);
    final requests = summary.requests.toString().padLeft(8);
    stdout.writeln('$label $reqPerSec $p50 $p95 $totalMs $requests');
  }

  if (options.jsonOutput) {
    stdout.writeln(
      jsonEncode(<String, Object>{
        'options': <String, Object>{
          'requests': options.requests,
          'concurrency': options.concurrency,
          'warmup': options.warmup,
          'iterations': options.iterations,
          'framework': options.framework,
          'nativeCallback': options.nativeCallback,
        },
        'results': summaries.map((summary) => summary.toJson()).toList(),
      }),
    );
  } else {
    for (var i = 0; i < summaries.length; i++) {
      final summary = summaries[i];
      final rank = i + 1;
      stdout.writeln(
        '  $rank. ${summary.label}: ${summary.requestsPerSecond.toStringAsFixed(0)} req/s, '
        'p95=${(summary.p95Micros / 1000).toStringAsFixed(2)} ms',
      );
    }
  }
}

Map<String, _ServerFactory> _buildCases(_BenchmarkOptions options) {
  final includeDartIo =
      options.framework == 'all' || options.framework == 'dart_io';
  final includeRouted =
      options.framework == 'all' || options.framework == 'routed';
  final includeRelic =
      options.framework == 'all' || options.framework == 'relic';
  final includeShelf =
      options.framework == 'all' || options.framework == 'shelf';
  final includeNativeDirect =
      options.framework == 'all' || options.framework == 'native_direct';

  final cases = <String, _ServerFactory>{};
  if (includeDartIo) {
    cases['dart_io_io'] = _startDartIoIo;
    cases['dart_io_native'] = () =>
        _startDartIoNative(nativeCallback: options.nativeCallback);
  }
  if (includeRouted) {
    cases['routed_io'] = _startRoutedIo;
    cases['routed_native'] = () =>
        _startRoutedNative(nativeCallback: options.nativeCallback);
  }
  if (includeRelic) {
    cases['relic_io'] = _startRelicIo;
    cases['relic_native'] = () =>
        _startRelicNative(nativeCallback: options.nativeCallback);
  }
  if (includeShelf) {
    cases['shelf_io'] = _startShelfIo;
    cases['shelf_native'] = () =>
        _startShelfNative(nativeCallback: options.nativeCallback);
  }
  if (includeNativeDirect) {
    cases['native_direct_rust'] = _startNativeDirectRust;
  }
  return cases;
}

Future<_RunningServer> _startDartIoIo() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final subscription = server.listen(_handleDartIoRequest);
  final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  return _RunningServer(
    baseUri: baseUri,
    close: () async {
      await subscription.cancel();
      await server.close(force: true);
    },
  );
}

Future<_RunningServer> _startDartIoNative({
  required bool nativeCallback,
}) async {
  final server = await NativeHttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
    http3: false,
    nativeCallback: nativeCallback,
  );
  final subscription = server.listen(_handleDartIoRequest);
  final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  return _RunningServer(
    baseUri: baseUri,
    close: () async {
      await subscription.cancel();
      await server.close(force: true);
    },
  );
}

Future<void> _handleDartIoRequest(HttpRequest request) async {
  if (request.uri.path == '/health') {
    request.response.headers.contentType = ContentType.json;
    request.response.write('{"ok":true}');
    await request.response.close();
    return;
  }
  request.response.statusCode = HttpStatus.notFound;
  request.response.write('not found');
  await request.response.close();
}

Future<_RunningServer> _startRoutedIo() async {
  final engine = Engine()
    ..get('/health', (ctx) async {
      await ctx.response.json(<String, Object>{'ok': true});
      return ctx.response;
    });
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final subscription = server.listen((request) {
    // ignore: discarded_futures
    engine.handleRequest(request);
  });
  final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  return _RunningServer(
    baseUri: baseUri,
    close: () async {
      await subscription.cancel();
      await server.close(force: true);
      await engine.close();
    },
  );
}

Future<_RunningServer> _startRoutedNative({
  required bool nativeCallback,
}) async {
  final engine = Engine()
    ..get('/health', (ctx) async {
      await ctx.response.json(<String, Object>{'ok': true});
      return ctx.response;
    });
  final server = await NativeHttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
    http3: false,
    nativeCallback: nativeCallback,
  );
  final subscription = server.listen((request) {
    // ignore: discarded_futures
    engine.handleRequest(request);
  });
  final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  return _RunningServer(
    baseUri: baseUri,
    close: () async {
      await subscription.cancel();
      await server.close(force: true);
      await engine.close();
    },
  );
}

Future<_RunningServer> _startRelicIo() async {
  final app = _buildRelicApp();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  await app.run(() => IOAdapter(server));
  final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  return _RunningServer(baseUri: baseUri, close: () => app.close());
}

Future<_RunningServer> _startRelicNative({required bool nativeCallback}) async {
  final app = _buildRelicApp();
  final server = await NativeHttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
    http3: false,
    nativeCallback: nativeCallback,
  );
  await app.run(() => IOAdapter(server));
  final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  return _RunningServer(baseUri: baseUri, close: () => app.close());
}

relic.RelicApp _buildRelicApp() {
  final app = relic.RelicApp()
    ..get('/health', (request) {
      return relic.Response.ok(
        body: relic.Body.fromString(
          '{"ok":true}',
          mimeType: relic.MimeType.json,
        ),
      );
    });
  return app;
}

Future<_RunningServer> _startShelfIo() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  shelf_io.serveRequests(server, _shelfHandler);
  final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  return _RunningServer(
    baseUri: baseUri,
    close: () => server.close(force: true),
  );
}

Future<_RunningServer> _startShelfNative({required bool nativeCallback}) async {
  final server = await NativeHttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
    http3: false,
    nativeCallback: nativeCallback,
  );
  shelf_io.serveRequests(server, _shelfHandler);
  final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  return _RunningServer(
    baseUri: baseUri,
    close: () => server.close(force: true),
  );
}

Future<_RunningServer> _startNativeDirectRust() async {
  final proxy = NativeProxyServer.start(
    host: InternetAddress.loopbackIPv4.address,
    port: 0,
    backendHost: InternetAddress.loopbackIPv4.address,
    backendPort: 9,
    benchmarkMode: benchmarkModeStaticNativeDirect,
  );
  final baseUri = Uri.parse('http://127.0.0.1:${proxy.port}');
  return _RunningServer(
    baseUri: baseUri,
    close: () async {
      proxy.close();
    },
    targetPath: '/bench',
  );
}

shelf.Response _shelfHandler(shelf.Request request) {
  if (request.url.path == 'health') {
    return shelf.Response.ok(
      '{"ok":true}',
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
  return shelf.Response.notFound('not found');
}

Future<void> _waitUntilUp(Uri uri) async {
  final client = HttpClient();
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == HttpStatus.ok) {
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('Timed out waiting for $uri');
  } finally {
    client.close(force: true);
  }
}

Future<_RunResult> _runLoad({
  required Uri baseUri,
  required String targetPath,
  required int requests,
  required int concurrency,
}) async {
  final targetUri = baseUri.replace(path: targetPath);
  final client = HttpClient()..maxConnectionsPerHost = concurrency * 2;
  final latencies = List<int>.filled(requests, 0, growable: false);
  var nextRequest = 0;
  final total = Stopwatch()..start();

  Future<void> worker() async {
    while (true) {
      final index = nextRequest;
      if (index >= requests) {
        return;
      }
      nextRequest = index + 1;

      final latency = Stopwatch()..start();
      final request = await client.getUrl(targetUri);
      final response = await request.close();
      await response.drain<void>();
      latency.stop();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'Unexpected status ${response.statusCode} for $targetUri',
        );
      }
      latencies[index] = latency.elapsedMicroseconds;
    }
  }

  try {
    await Future.wait(
      List<Future<void>>.generate(concurrency, (_) => worker()),
    );
  } finally {
    total.stop();
    client.close(force: true);
  }

  final sorted = List<int>.from(latencies)..sort();
  final p50Index = ((sorted.length - 1) * 0.50).round();
  final p95Index = ((sorted.length - 1) * 0.95).round();
  final totalMicros = total.elapsedMicroseconds;
  final requestsPerSecond = requests * 1000000 / totalMicros;

  return _RunResult(
    requests: requests,
    totalMicros: totalMicros,
    requestsPerSecond: requestsPerSecond,
    p50Micros: sorted[p50Index],
    p95Micros: sorted[p95Index],
  );
}

_CaseSummary _summarize(String label, List<_RunResult> runs) {
  final reqPerSecValues =
      runs.map((run) => run.requestsPerSecond).toList(growable: false)..sort();
  final p50Values = runs.map((run) => run.p50Micros).toList(growable: false)
    ..sort();
  final p95Values = runs.map((run) => run.p95Micros).toList(growable: false)
    ..sort();
  final totalValues = runs.map((run) => run.totalMicros).toList(growable: false)
    ..sort();
  final medianIndex = (runs.length - 1) ~/ 2;
  return _CaseSummary(
    label: label,
    requestsPerSecond: reqPerSecValues[medianIndex],
    p50Micros: p50Values[medianIndex],
    p95Micros: p95Values[medianIndex],
    totalMicros: totalValues[medianIndex],
    requests: runs[medianIndex].requests,
  );
}

_BenchmarkOptions _parseArgs(List<String> args) {
  var requests = 2500;
  var concurrency = 64;
  var warmup = 300;
  var iterations = 5;
  var framework = 'all';
  var nativeCallback = true;
  var jsonOutput = false;

  for (final arg in args) {
    if (arg.startsWith('--requests=')) {
      requests = int.parse(arg.substring('--requests='.length));
      continue;
    }
    if (arg.startsWith('--concurrency=')) {
      concurrency = int.parse(arg.substring('--concurrency='.length));
      continue;
    }
    if (arg.startsWith('--warmup=')) {
      warmup = int.parse(arg.substring('--warmup='.length));
      continue;
    }
    if (arg.startsWith('--iterations=')) {
      iterations = int.parse(arg.substring('--iterations='.length));
      continue;
    }
    if (arg.startsWith('--framework=')) {
      framework = arg.substring('--framework='.length);
      continue;
    }
    if (arg.startsWith('--native-callback=')) {
      nativeCallback = _parseBool(arg.substring('--native-callback='.length));
      continue;
    }
    if (arg == '--json') {
      jsonOutput = true;
      continue;
    }
    if (arg == '--help' || arg == '-h') {
      _printUsageAndExit(0);
    }
    stderr.writeln('Unknown argument: $arg');
    _printUsageAndExit(64);
  }

  if (requests <= 0 || concurrency <= 0 || warmup < 0 || iterations <= 0) {
    stderr.writeln('Invalid numeric options.');
    _printUsageAndExit(64);
  }

  if (framework != 'all' &&
      framework != 'dart_io' &&
      framework != 'routed' &&
      framework != 'relic' &&
      framework != 'shelf' &&
      framework != 'native_direct') {
    stderr.writeln('Invalid --framework value: $framework');
    _printUsageAndExit(64);
  }

  return _BenchmarkOptions(
    requests: requests,
    concurrency: concurrency,
    warmup: warmup,
    iterations: iterations,
    framework: framework,
    nativeCallback: nativeCallback,
    jsonOutput: jsonOutput,
  );
}

bool _parseBool(String value) {
  switch (value) {
    case 'true':
    case '1':
    case 'yes':
      return true;
    case 'false':
    case '0':
    case 'no':
      return false;
  }
  throw ArgumentError('Invalid boolean value: $value');
}

Never _printUsageAndExit(int code) {
  stdout.writeln(
    'Usage: dart run benchmark/framework_transport_benchmark.dart [options]\n'
    'Options:\n'
    '  --requests=<int>           Requests per iteration (default: 2500)\n'
    '  --concurrency=<int>        Parallel clients (default: 64)\n'
    '  --warmup=<int>             Warmup requests (default: 300)\n'
    '  --iterations=<int>         Iteration count (default: 5)\n'
    '  --framework=all|dart_io|routed|relic|shelf|native_direct\n'
    '                             Framework cases to run (default: all)\n'
    '  --native-callback=true|false\n'
    '                             Native server callback mode (default: true)\n'
    '  --json                     Emit machine-readable summary JSON\n'
    '  --help, -h                 Show this help',
  );
  exit(code);
}
