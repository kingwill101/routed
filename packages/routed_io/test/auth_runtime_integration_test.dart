import 'dart:convert';
import 'dart:io';

import 'package:routed_auth/testing.dart';
import 'package:routed_io/routed_io.dart';
import 'package:test/test.dart';

void main() {
  test('dart:io listener satisfies the routed auth runtime contract', () async {
    final engine = createAuthRuntimeConformanceEngine();
    await engine.initialize();
    final handle = await serveIo(
      engine,
      host: '127.0.0.1',
      port: 0,
      echo: false,
    );
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await handle.close(force: true);
      await engine.close();
    });
    final origin = Uri.parse('http://127.0.0.1:${handle.port}');

    await verifyAuthRuntimeConformance(
      origin: origin,
      send: (request) => _send(client, origin, request),
    );
  });

  test('dart:io listener satisfies the auth plugin runtime contract', () async {
    final engine = createAuthPluginRuntimeConformanceEngine();
    final engineWithoutTwoFactor = createAuthPluginRuntimeConformanceEngine(
      includeTwoFactor: false,
    );
    await engine.initialize();
    await engineWithoutTwoFactor.initialize();
    final handle = await serveIo(
      engine,
      host: '127.0.0.1',
      port: 0,
      echo: false,
    );
    final handleWithoutTwoFactor = await serveIo(
      engineWithoutTwoFactor,
      host: '127.0.0.1',
      port: 0,
      echo: false,
    );
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await handle.close(force: true);
      await handleWithoutTwoFactor.close(force: true);
      await engine.close();
      await engineWithoutTwoFactor.close();
    });
    final origin = Uri.parse('http://127.0.0.1:${handle.port}');
    final originWithoutTwoFactor = Uri.parse(
      'http://127.0.0.1:${handleWithoutTwoFactor.port}',
    );

    await verifyAuthPluginRuntimeConformance(
      origin: origin,
      send: (request) => _send(client, origin, request),
      sendWithoutTwoFactor: (request) =>
          _send(client, originWithoutTwoFactor, request),
    );
  });
}

Future<AuthRuntimeConformanceResponse> _send(
  HttpClient client,
  Uri origin,
  AuthRuntimeConformanceRequest source,
) async {
  final request = await client.openUrl(
    source.method,
    origin.resolve(source.path),
  );
  request.followRedirects = false;
  source.headers.forEach((name, values) {
    for (final value in values) {
      request.headers.add(name, value);
    }
  });
  final body = source.body;
  if (body != null) request.add(utf8.encode(body));
  final response = await request.close();
  final headers = <String, List<String>>{};
  response.headers.forEach((name, values) {
    headers[name] = List<String>.from(values);
  });
  return AuthRuntimeConformanceResponse(
    statusCode: response.statusCode,
    headers: headers,
    body: await utf8.decodeStream(response),
  );
}
