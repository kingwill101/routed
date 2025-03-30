import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  late TestClient client;

  tearDown(() async {
    await client.close();
  });

  group('Engine Configuration Tests', () {
    group('RedirectTrailingSlash', () {
      test('enabled - redirects GET requests with 301', () async {
        final engine =
            Engine(config: EngineConfig(redirectTrailingSlash: true));
        engine.get('/users', (ctx) => ctx.string('users'));

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.get('/users/');
        response
          ..assertStatus(301)
          ..assertHeader('Location', '/users');
      });

      test('enabled - redirects POST requests with 307', () async {
        final engine =
            Engine(config: EngineConfig(redirectTrailingSlash: true));
        engine.post('/users', (ctx) => ctx.string('created'));

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.post('/users/', null);
        response
          ..assertStatus(307)
          ..assertHeader('Location', '/users');
      });

      test('disabled - returns 404 for trailing slash', () async {
        final engine =
            Engine(config: EngineConfig(redirectTrailingSlash: false));
        engine.get('/users', (ctx) => ctx.string('users'));

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.get('/users/');
        response.assertStatus(404);
      });
    });

    group('HandleMethodNotAllowed', () {
      test('enabled - returns 405 with Allow header', () async {
        final engine =
            Engine(config: EngineConfig(handleMethodNotAllowed: true));
        engine.get('/users', (ctx) => ctx.string('users'));
        engine.post('/users', (ctx) => ctx.string('created'));

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.put('/users', null);
        response
          ..assertStatus(405)
          ..assertHeaderContains('Allow', ['GET', 'POST']);
      });

      test('disabled - returns 404 for wrong method', () async {
        final engine =
            Engine(config: EngineConfig(handleMethodNotAllowed: false));
        engine.get('/users', (ctx) => ctx.string('users'));

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.post('/users', null);
        response.assertStatus(404);
      });
    });

    group('ForwardedByClientIP', () {
      test('processes X-Forwarded-For header', () async {
        final engine = Engine(
            config: EngineConfig(
                features: const EngineFeatures(
                  enableProxySupport: true,
                  enableTrustedPlatform: true,
                ),
                forwardedByClientIP: true,
                remoteIPHeaders: ['X-Forwarded-For']));
        engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

        client = TestClient(
          RoutedRequestHandler(engine),
          options:
              TransportOptions(remoteAddress: InternetAddress('192.168.1.2')),
        );

        final response = await client.get('/ip', headers: {
          'X-Forwarded-For': ['1.2.3.4']
        });
        response
          ..assertStatus(200)
          ..assertBodyEquals('1.2.3.4');
      });

      test('processes X-Real-IP header', () async {
        final engine = Engine(
            config: EngineConfig(
                features: const EngineFeatures(
                  enableProxySupport: true,
                  enableTrustedPlatform: true,
                ),
                forwardedByClientIP: true,
                remoteIPHeaders: ['X-Real-IP']));
        engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

        client = TestClient(
          RoutedRequestHandler(engine),
          options:
              TransportOptions(remoteAddress: InternetAddress('192.168.1.2')),
        );

        final response = await client.get('/ip', headers: {
          'X-Real-IP': ['5.6.7.8']
        });
        response.assertBodyEquals('5.6.7.8');
      });

      test('respects forwardedByClientIP setting when disabled', () async {
        final engine = Engine(config: EngineConfig(forwardedByClientIP: false));
        engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

        client = TestClient(
          RoutedRequestHandler(engine),
          options:
              TransportOptions(remoteAddress: InternetAddress('192.168.1.2')),
        );

        final response = await client.get('/ip', headers: {
          'X-Forwarded-For': ['1.2.3.4'],
          'X-Real-IP': ['5.6.7.8']
        });
        response.assertBodyEquals('192.168.1.2');
      });
    });

    group('Combined Configuration', () {
      test('multiple options work together', () async {
        final engine = Engine(
            config: EngineConfig(
                features: const EngineFeatures(
                  enableProxySupport: true,
                  enableTrustedPlatform: true,
                ),
                redirectTrailingSlash: true,
                handleMethodNotAllowed: true,
                forwardedByClientIP: true,
                remoteIPHeaders: ['X-Real-IP']));
        engine.get('/users', (ctx) => ctx.string('users'));
        engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

        client = TestClient(
          RoutedRequestHandler(engine),
          options:
              TransportOptions(remoteAddress: InternetAddress('192.168.1.2')),
        );

        // Test trailing slash redirect
        var response = await client.get('/users/');
        response
          ..assertStatus(301)
          ..assertHeader('Location', '/users');

        // Test method not allowed
        response = await client.post('/users', null);
        response
          ..assertStatus(405)
          ..assertHeaderContains('Allow', ['GET']);

        // Test IP forwarding
        response = await client.get('/ip', headers: {
          'X-Real-IP': ['1.2.3.4']
        });
        response.assertBodyEquals('1.2.3.4');

        // Test normal request
        response = await client.get('/users');
        response
          ..assertStatus(200)
          ..assertBodyEquals('users');
      });
    });
  });

  group('Proxy Trust Tests', () {
    test('default configuration trusts all proxies', () async {
      final engine = Engine(
          config: EngineConfig(
        features: const EngineFeatures(
          enableProxySupport: true,
          enableTrustedPlatform: true,
        ),
      ));
      engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

      client = TestClient(
        RoutedRequestHandler(engine),
        options:
            TransportOptions(remoteAddress: InternetAddress('192.168.1.2')),
      );

      final response = await client.get('/ip', headers: {
        'X-Forwarded-For': ['1.2.3.4']
      });
      response.assertBodyEquals('1.2.3.4');
    });

    test('restricted proxy list only trusts specified IPs', () async {
      final engine = Engine(
          config: EngineConfig(
              features: const EngineFeatures(
                enableProxySupport: true,
                enableTrustedPlatform: true,
              ),
              trustedProxies: ['10.0.0.0/8'],
              remoteIPHeaders: ['X-Forwarded-For']));
      engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

      client = TestClient(
        RoutedRequestHandler(engine),
        options: TransportOptions(remoteAddress: InternetAddress('10.0.0.2')),
      );

      final response = await client.get('/ip', headers: {
        'X-Forwarded-For': ['1.2.3.4']
      });
      response.assertBodyEquals('1.2.3.4');
    });

    test('untrusted proxy returns immediate client IP', () async {
      final engine = Engine(
          config: EngineConfig(
              features: const EngineFeatures(
                enableProxySupport: true,
                enableTrustedPlatform: true,
              ),
              trustedProxies: ['10.0.0.0/8'],
              remoteIPHeaders: ['X-Forwarded-For']));
      engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

      client = TestClient(
        RoutedRequestHandler(engine),
        options:
            TransportOptions(remoteAddress: InternetAddress('192.168.1.2')),
      );

      final response = await client.get('/ip', headers: {
        'X-Forwarded-For': ['1.2.3.4']
      });
      response.assertBodyEquals('192.168.1.2');
    });

    test('trusted platform headers take precedence', () async {
      final engine = Engine(
          config: EngineConfig(
              features: const EngineFeatures(
                enableProxySupport: true,
                enableTrustedPlatform: true,
              ),
              trustedPlatform: 'CF-Connecting-IP',
              remoteIPHeaders: ['X-Forwarded-For']));
      engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

      client = TestClient(
        RoutedRequestHandler(engine),
        options: TransportOptions(remoteAddress: InternetAddress('10.0.0.2')),
      );

      final response = await client.get('/ip', headers: {
        'CF-Connecting-IP': ['2.2.2.2'],
        'X-Forwarded-For': ['1.1.1.1']
      });
      response.assertBodyEquals('2.2.2.2');
    });

    test('header order is respected', () async {
      final engine = Engine(
          config: EngineConfig(
              features: const EngineFeatures(
                enableProxySupport: true,
                enableTrustedPlatform: true,
              ),
              remoteIPHeaders: ['X-Real-IP', 'X-Forwarded-For']));
      engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

      client = TestClient(
        RoutedRequestHandler(engine),
        options: TransportOptions(remoteAddress: InternetAddress('10.0.0.2')),
      );

      final response = await client.get('/ip', headers: {
        'X-Real-IP': ['5.5.5.5'],
        'X-Forwarded-For': ['1.1.1.1']
      });
      response.assertBodyEquals('5.5.5.5');
    });
  });

  test('proxy support requires explicit feature flag', () {
    final engine = Engine(
        config:
            EngineConfig(features: const EngineFeatures(enableProxySupport: true)));

    engine.config.trustedProxies = ['10.0.0.0/8'];
    expect(engine.config.trustedProxies, contains('10.0.0.0/8'));
  });

  test('trusted platform requires explicit feature flag', () {
    final engine = Engine(
        config: EngineConfig(
            features: const EngineFeatures(enableTrustedPlatform: true)));

    engine.config.trustedPlatform = 'CF-Connecting-IP';
    expect(engine.config.trustedPlatform, equals('CF-Connecting-IP'));
  });
}
