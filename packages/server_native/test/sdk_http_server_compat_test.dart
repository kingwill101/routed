import 'dart:async';
import 'dart:io';

import 'package:server_native/server_native.dart';
import 'package:test/test.dart';

/// Parity checks ported from Dart SDK standalone IO tests:
/// - tests/standalone/io/http_server_test.dart
/// - tests/standalone/io/http_bind_test.dart
/// - tests/standalone/io/http_connection_header_test.dart
/// - tests/standalone/io/http_content_length_test.dart
///
/// The suite intentionally keeps known native gaps visible via skipped tests
/// so future parity work can be enabled by removing skip markers.

enum _Backend {
  dartIo('dart:io'),
  native('server_native');

  const _Backend(this.label);
  final String label;
}

Future<HttpServer> _bindServer(
  _Backend backend,
  dynamic address,
  int port, {
  int backlog = 0,
  bool v6Only = false,
  bool shared = false,
}) {
  switch (backend) {
    case _Backend.dartIo:
      return HttpServer.bind(
        address,
        port,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
      );
    case _Backend.native:
      return NativeHttpServer.bind(
        address,
        port,
        backlog: backlog,
        v6Only: v6Only,
        shared: shared,
        http3: false,
        nativeCallback: true,
      );
  }
}

Future<bool> _supportsIPv6() async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv6, 0);
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}

Future<(int statusCode, HttpHeaders headers, List<int> bodyBytes)> _requestOnce(
  HttpServer server,
) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    final response = await request.close();
    final bodyBytes = await response.fold<List<int>>(
      <int>[],
      (list, chunk) => list..addAll(chunk),
    );
    return (response.statusCode, response.headers, bodyBytes);
  } finally {
    client.close(force: true);
  }
}

Future<HttpHeaders> _fetchHeadersSnapshot(
  _Backend backend, {
  bool clearDefaultHeaders = false,
  Map<String, String>? addDefaultHeaders,
}) async {
  final server = await _bindServer(backend, InternetAddress.loopbackIPv4, 0);
  final sub = server.listen((request) async {
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
  });
  try {
    if (clearDefaultHeaders) {
      server.defaultResponseHeaders.clear();
    }
    addDefaultHeaders?.forEach(server.defaultResponseHeaders.set);
    final result = await _requestOnce(server);
    expect(result.$1, HttpStatus.ok);
    return result.$2;
  } finally {
    await sub.cancel();
    await server.close(force: true);
  }
}

Future<List<int>> _fetchBodyBytes(
  _Backend backend, {
  required bool clearDefaultHeaders,
  required String body,
}) async {
  final server = await _bindServer(backend, InternetAddress.loopbackIPv4, 0);
  if (clearDefaultHeaders) {
    server.defaultResponseHeaders.clear();
  }
  final sub = server.listen((request) async {
    request.response.write(body);
    await request.response.close();
  });
  try {
    final result = await _requestOnce(server);
    expect(result.$1, HttpStatus.ok);
    return result.$3;
  } finally {
    await sub.cancel();
    await server.close(force: true);
  }
}

void _setConnectionHeaders(HttpHeaders headers) {
  headers.add(HttpHeaders.connectionHeader, 'my-connection-header1');
  headers.add('My-Connection-Header1', 'some-value1');
  headers.add(HttpHeaders.connectionHeader, 'my-connection-header2');
  headers.add('My-Connection-Header2', 'some-value2');
}

void _checkExpectedConnectionHeaders(
  HttpHeaders headers,
  bool persistentConnection,
) {
  expect(headers.value('My-Connection-Header1'), 'some-value1');
  expect(headers.value('My-Connection-Header2'), 'some-value2');

  final connection = headers[HttpHeaders.connectionHeader] ?? const <String>[];
  expect(
    connection.any((value) => value.toLowerCase() == 'my-connection-header1'),
    isTrue,
  );
  expect(
    connection.any((value) => value.toLowerCase() == 'my-connection-header2'),
    isTrue,
  );

  if (persistentConnection) {
    expect(connection.length, 2);
  } else {
    expect(connection.length, 3);
    expect(connection.any((value) => value.toLowerCase() == 'close'), isTrue);
  }
}

Future<int> _singleRequestStatus(String host, int port) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      'GET',
      Uri.parse('http://${host.contains(':') ? '[$host]' : host}:$port/'),
    );
    final response = await request.close();
    final statusCode = response.statusCode;
    await response.drain<void>();
    return statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('SDK HttpServer compatibility', () {
    for (final backend in _Backend.values) {
      test('${backend.label}: default response headers', () async {
        final headers = await _fetchHeadersSnapshot(backend);
        expect(
          headers[HttpHeaders.contentTypeHeader],
          equals(const <String>['text/plain; charset=utf-8']),
        );
        expect(
          headers['x-frame-options'],
          equals(const <String>['SAMEORIGIN']),
        );
        expect(
          headers['x-content-type-options'],
          equals(const <String>['nosniff']),
        );
        expect(
          headers['x-xss-protection'],
          equals(const <String>['1; mode=block']),
        );
      });

      test('${backend.label}: cleared default response headers', () async {
        final headers = await _fetchHeadersSnapshot(
          backend,
          clearDefaultHeaders: true,
        );
        expect(headers[HttpHeaders.contentTypeHeader], isNull);
        expect(headers['x-frame-options'], isNull);
        expect(headers['x-content-type-options'], isNull);
        expect(headers['x-xss-protection'], isNull);
      });

      test(
        '${backend.label}: cleared + custom default response headers',
        () async {
          final headers = await _fetchHeadersSnapshot(
            backend,
            clearDefaultHeaders: true,
            addDefaultHeaders: const <String, String>{'a': 'b'},
          );
          expect(headers[HttpHeaders.contentTypeHeader], isNull);
          expect(headers['x-frame-options'], isNull);
          expect(headers['x-content-type-options'], isNull);
          expect(headers['x-xss-protection'], isNull);
          expect(headers['a'], equals(const <String>['b']));
        },
      );

      test(
        '${backend.label}: response.write uses UTF-8 with default content-type',
        () async {
          final bytes = await _fetchBodyBytes(
            backend,
            clearDefaultHeaders: false,
            body: 'æøå',
          );
          expect(bytes, equals(const <int>[195, 166, 195, 184, 195, 165]));
        },
      );

      test(
        '${backend.label}: response.write uses latin1 when content-type is absent',
        () async {
          final bytes = await _fetchBodyBytes(
            backend,
            clearDefaultHeaders: true,
            body: 'æøå',
          );
          expect(bytes, equals(const <int>[230, 248, 229]));
        },
      );

      for (final clientPersistentConnection in <bool>[false, true]) {
        test(
          '${backend.label}: connection headers/persistentConnection '
          '(clientPersistentConnection=$clientPersistentConnection)',
          () async {
            final server = await _bindServer(
              backend,
              InternetAddress.loopbackIPv4,
              0,
            );
            final handled = Completer<void>();
            final sub = server.listen((request) async {
              expect(request.persistentConnection, clientPersistentConnection);
              expect(
                request.response.persistentConnection,
                clientPersistentConnection,
              );
              _checkExpectedConnectionHeaders(
                request.headers,
                request.persistentConnection,
              );

              if (request.persistentConnection) {
                request.response.persistentConnection = false;
              }
              _setConnectionHeaders(request.response.headers);
              await request.response.close();
              handled.complete();
            });

            final client = HttpClient();
            try {
              final req = await client.getUrl(
                Uri.parse('http://127.0.0.1:${server.port}/'),
              );
              _setConnectionHeaders(req.headers);
              req.persistentConnection = clientPersistentConnection;
              final response = await req.close();
              expect(response.persistentConnection, isFalse);
              _checkExpectedConnectionHeaders(
                response.headers,
                response.persistentConnection,
              );
              await response.drain<void>();
              await handled.future.timeout(const Duration(seconds: 3));
            } finally {
              client.close(force: true);
              await sub.cancel();
              await server.close(force: true);
            }
          },
          skip: backend == _Backend.native
              ? 'Known parity gap: connection-header/persistentConnection '
                    'behavior diverges'
              : false,
        );
      }

      test(
        '${backend.label}: response.done errors when content-length is 0 and body is written',
        () async {
          final doneError = Completer<Object>();
          final server = await _bindServer(
            backend,
            InternetAddress.loopbackIPv4,
            0,
          );
          final sub = server.listen((request) async {
            request.response.contentLength = 0;
            request.response.done.catchError((error) {
              if (!doneError.isCompleted) {
                doneError.complete(error);
              }
            });
            try {
              request.response.write('x');
            } catch (error) {
              if (!doneError.isCompleted) {
                doneError.complete(error);
              }
            }
            try {
              await request.response.close();
            } catch (error) {
              if (!doneError.isCompleted) {
                doneError.complete(error);
              }
            }
          });

          final client = HttpClient();
          try {
            final req = await client.getUrl(
              Uri.parse('http://127.0.0.1:${server.port}/'),
            );
            try {
              final response = await req.close();
              await response.drain<void>();
            } catch (_) {}
            final error = await doneError.future.timeout(
              const Duration(seconds: 3),
            );
            expect(error, isA<HttpException>());
          } finally {
            client.close(force: true);
            await sub.cancel();
            await server.close(force: true);
          }
        },
      );

      test(
        '${backend.label}: response.done errors when content-length is greater than body',
        () async {
          final doneError = Completer<Object>();
          final server = await _bindServer(
            backend,
            InternetAddress.loopbackIPv4,
            0,
          );
          final sub = server.listen((request) async {
            request.response.contentLength = 5;
            request.response.done.catchError((error) {
              if (!doneError.isCompleted) {
                doneError.complete(error);
              }
            });
            try {
              request.response.write('x');
              await request.response.close();
            } catch (error) {
              if (!doneError.isCompleted) {
                doneError.complete(error);
              }
            }
          });

          final client = HttpClient();
          try {
            final req = await client.getUrl(
              Uri.parse('http://127.0.0.1:${server.port}/'),
            );
            try {
              final response = await req.close();
              await response.drain<void>();
            } catch (_) {}
            final error = await doneError.future.timeout(
              const Duration(seconds: 3),
            );
            expect(error, isA<HttpException>());
          } finally {
            client.close(force: true);
            await sub.cancel();
            await server.close(force: true);
          }
        },
      );
    }

    test(
      'bind(shared:true) parity on IPv4/IPv6 loopback',
      () async {
        final hosts = <String>['127.0.0.1'];
        if (await _supportsIPv6()) {
          hosts.add('::1');
        }

        for (final backend in _Backend.values) {
          for (final host in hosts) {
            for (final v6Only in <bool>[false, true]) {
              final server1 = await _bindServer(
                backend,
                host,
                0,
                v6Only: v6Only,
                shared: true,
              );
              final port = server1.port;
              expect(port, greaterThan(0));

              final server2 = await _bindServer(
                backend,
                host,
                port,
                v6Only: v6Only,
                shared: true,
              );
              expect(server2.port, port);
              expect(server2.address.address, server1.address.address);

              final sub1 = server1.listen((request) async {
                request.response.statusCode = 501;
                await request.response.close();
              });
              final status1 = await _singleRequestStatus(host, port);
              expect(status1, 501);
              await sub1.cancel();
              await server1.close(force: true);

              final sub2 = server2.listen((request) async {
                request.response.statusCode = 502;
                await request.response.close();
              });
              final status2 = await _singleRequestStatus(host, port);
              expect(status2, 502);
              await sub2.cancel();
              await server2.close(force: true);
            }
          }
        }
      },
      skip: 'Known parity gap: NativeHttpServer shared-bind lifecycle differs',
    );
  });
}
