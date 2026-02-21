import 'dart:async';
import 'dart:io';

import 'package:server_native/server_native.dart';
import 'package:test/test.dart';

typedef _BindServer = Future<HttpServer> Function();

Future<(int statusCode, List<String>? transferEncoding)>
_runTransferEncodingProbe(
  _BindServer bindServer,
  String transferEncodingValue,
) async {
  final server = await bindServer();
  final requestHeaders = Completer<List<String>?>();
  final subscription = server.listen((request) async {
    requestHeaders.complete(
      request.headers[HttpHeaders.transferEncodingHeader],
    );
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
  });

  final client = HttpClient();
  try {
    final request = await client
        .getUrl(Uri.parse('http://127.0.0.1:${server.port}/'))
        .timeout(const Duration(seconds: 3));
    request.headers.set(
      HttpHeaders.transferEncodingHeader,
      transferEncodingValue,
    );
    final response = await request.close().timeout(const Duration(seconds: 3));
    await response.drain<void>();
    final transferEncoding = await requestHeaders.future.timeout(
      const Duration(seconds: 3),
    );
    return (response.statusCode, transferEncoding);
  } finally {
    client.close(force: true);
    await subscription.cancel();
    await server.close(force: true);
  }
}

Future<(int statusCode, List<String>? transferEncoding)>
_runDartIoTransferEncodingProbe(String transferEncodingValue) {
  return _runTransferEncodingProbe(
    () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    transferEncodingValue,
  );
}

Future<(int statusCode, List<String>? transferEncoding)>
_runNativeTransferEncodingProbe(String transferEncodingValue) {
  return _runTransferEncodingProbe(
    () => NativeHttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      http3: false,
      nativeCallback: true,
    ),
    transferEncodingValue,
  );
}

void main() {
  group('Native transfer-encoding parity', () {
    test('GET custom transfer-encoding matches dart:io behavior', () async {
      final dartIo = await _runDartIoTransferEncodingProbe('custom-value');
      final native = await _runNativeTransferEncodingProbe('custom-value');

      expect(native.$1, dartIo.$1);
      expect(native.$2, equals(dartIo.$2));
    });

    test(
      'GET gzip, chunked transfer-encoding matches dart:io behavior',
      () async {
        final dartIo = await _runDartIoTransferEncodingProbe('gzip, chunked');
        final native = await _runNativeTransferEncodingProbe('gzip, chunked');

        expect(native.$1, dartIo.$1);
        expect(native.$2, equals(dartIo.$2));
      },
    );
  });
}
