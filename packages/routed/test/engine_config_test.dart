import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/src/security/trusted_proxy_resolver.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'test_engine.dart';

void main() {
  late TestClient client;

  tearDown(() async {
    await client.close();
  });

  group('Engine Configuration Tests', () {
    group('RedirectTrailingSlash', () {
      test('enabled - redirects GET requests with 301', () async {
        final engine = testEngine(
          configItems: {
            'routing': {'redirect_trailing_slash': true},
          },
        );
        engine.get('/users', (ctx) => ctx.string('users'));

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.get('/users/');
        response
          ..assertStatus(301)
          ..assertHeader('Location', '/users');
      });

      test('enabled - redirects POST requests with 307', () async {
        final engine = testEngine(
          configItems: {
            'routing': {'redirect_trailing_slash': true},
          },
        );
        engine.post('/users', (ctx) => ctx.string('created'));

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.post('/users/', null);
        response
          ..assertStatus(307)
          ..assertHeader('Location', '/users');
      });

      test('disabled - returns 404 for trailing slash', () async {
        final engine = testEngine(
          configItems: {
            'routing': {'redirect_trailing_slash': false},
          },
        );
        engine.get('/users', (ctx) => ctx.string('users'));

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.get('/users/');
        response.assertStatus(404);
      });
    });

    group('HandleMethodNotAllowed', () {
      test('enabled - returns 405 with Allow header', () async {
        final engine = testEngine(
          configItems: {
            'routing': {'handle_method_not_allowed': true},
          },
        );
        engine.get('/users', (ctx) => ctx.string('users'));
        engine.post('/users', (ctx) => ctx.string('created'));

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.put('/users', null);
        response
          ..assertStatus(405)
          ..assertHeaderContains('Allow', ['GET', 'POST']);
      });

      test('disabled - returns 404 for wrong method', () async {
        final engine = testEngine(
          configItems: {
            'routing': {'handle_method_not_allowed': false},
          },
        );
        engine.get('/users', (ctx) => ctx.string('users'));

        client = TestClient(RoutedRequestHandler(engine));
        final response = await client.post('/users', null);
        response.assertStatus(404);
      });
    });

    group('ForwardedByClientIP', () {
      test('processes X-Forwarded-For header', () async {
        final engine = testEngine(
          configItems: {
            'security': {
              'trusted_proxies': {
                'enabled': true,
                'forward_client_ip': true,
                'proxies': ['0.0.0.0/0', '::/0'],
                'headers': ['X-Forwarded-For'],
              },
            },
          },
        );
        expect(engine.container.has<TrustedProxyResolver>(), isTrue);
        engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

        client = TestClient(
          RoutedRequestHandler(engine),
          options: TransportOptions(
            remoteAddress: InternetAddress('192.168.1.2'),
          ),
        );

        final response = await client.get(
          '/ip',
          headers: {
            'X-Forwarded-For': ['1.2.3.4'],
          },
        );
        response
          ..assertStatus(200)
          ..assertBodyEquals('1.2.3.4');
      });

      test('processes X-Real-IP header', () async {
        final engine = testEngine(
          configItems: {
            'security': {
              'trusted_proxies': {
                'enabled': true,
                'forward_client_ip': true,
                'proxies': ['0.0.0.0/0', '::/0'],
                'headers': ['X-Real-IP'],
              },
            },
          },
        );
        engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

        client = TestClient(
          RoutedRequestHandler(engine),
          options: TransportOptions(
            remoteAddress: InternetAddress('192.168.1.2'),
          ),
        );

        final response = await client.get(
          '/ip',
          headers: {
            'X-Real-IP': ['5.6.7.8'],
          },
        );
        response.assertBodyEquals('5.6.7.8');
      });

      test('respects forwardedByClientIP setting when disabled', () async {
        final engine = testEngine(
          configItems: {
            'security': {
              'trusted_proxies': {
                'enabled': true,
                'forward_client_ip': false,
                'proxies': ['0.0.0.0/0', '::/0'],
              },
            },
          },
        );
        engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

        client = TestClient(
          RoutedRequestHandler(engine),
          options: TransportOptions(
            remoteAddress: InternetAddress('192.168.1.2'),
          ),
        );

        final response = await client.get(
          '/ip',
          headers: {
            'X-Forwarded-For': ['1.2.3.4'],
            'X-Real-IP': ['5.6.7.8'],
          },
        );
        response.assertBodyEquals('192.168.1.2');
      });

      test(
        'falls back to remote address when proxy support disabled',
        () async {
          final engine = testEngine(
            configItems: {
              'security': {
                'trusted_proxies': {'enabled': false},
              },
            },
          );
          engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

          client = TestClient(
            RoutedRequestHandler(engine),
            options: TransportOptions(
              remoteAddress: InternetAddress('192.168.1.2'),
            ),
          );

          final response = await client.get(
            '/ip',
            headers: {
              'X-Forwarded-For': ['1.2.3.4'],
              'X-Real-IP': ['5.6.7.8'],
            },
          );

          response
            ..assertStatus(200)
            ..assertBodyEquals('192.168.1.2');
        },
      );
    });

    group('Combined Configuration', () {
      test('multiple options work together', () async {
        final engine = testEngine(
          configItems: {
            'routing': {
              'redirect_trailing_slash': true,
              'handle_method_not_allowed': true,
            },
            'security': {
              'trusted_proxies': {
                'enabled': true,
                'forward_client_ip': true,
                'proxies': ['0.0.0.0/0', '::/0'],
                'headers': ['X-Real-IP'],
              },
            },
          },
        );
        engine.get('/users', (ctx) => ctx.string('users'));
        engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

        client = TestClient(
          RoutedRequestHandler(engine),
          options: TransportOptions(
            remoteAddress: InternetAddress('192.168.1.2'),
          ),
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
        response = await client.get(
          '/ip',
          headers: {
            'X-Real-IP': ['1.2.3.4'],
          },
        );
        response.assertBodyEquals('1.2.3.4');

        // Test normal request
        response = await client.get('/users');
        response
          ..assertStatus(200)
          ..assertBodyEquals('users');
      });
    });

    group('UploadsConfig', () {
      test('reads limits from config map', () async {
        final engine = testEngine(
          configItems: {
            'uploads': {
              'max_memory': 2 * 1024,
              'max_file_size': 4 * 1024,
              'allowed_extensions': ['txt', 'csv'],
            },
          },
        );
        addTearDown(() async => await engine.close());
        await engine.initialize();

        expect(engine.config.multipart.maxMemory, equals(2 * 1024));
        expect(engine.config.multipart.maxFileSize, equals(4 * 1024));
        expect(
          engine.config.multipart.allowedExtensions,
          equals({'txt', 'csv'}),
        );
      });

      test('withMultipart updates config and engine values', () async {
        final engine = testEngine(
          options: [
            withMultipart(
              maxMemory: 1024,
              maxFileSize: 2048,
              allowedExtensions: {'md', 'txt'},
            ),
          ],
        );
        addTearDown(() async => await engine.close());
        await engine.initialize();

        expect(engine.appConfig.getInt('uploads.max_memory'), equals(1024));
        expect(engine.appConfig.getInt('uploads.max_file_size'), equals(2048));
        final extensions =
            (engine.appConfig.get('uploads.allowed_extensions')
                    as List<dynamic>?)
                ?.map((e) => e.toString())
                .toSet();
        expect(extensions, equals({'md', 'txt'}));
        expect(
          engine.config.multipart.allowedExtensions,
          equals({'md', 'txt'}),
        );
        expect(engine.config.multipart.maxMemory, equals(1024));
        expect(engine.config.multipart.maxFileSize, equals(2048));
      });
    });

    group('CorsConfig', () {
      test('reads settings from cors map', () async {
        final engine = testEngine(
          configItems: {
            'cors': {
              'enabled': true,
              'allowed_origins': ['https://app.dev'],
              'allowed_methods': ['GET', 'POST'],
              'allowed_headers': ['Authorization'],
              'allow_credentials': true,
              'max_age': 600,
              'exposed_headers': ['X-Token'],
            },
          },
        );
        addTearDown(() async => await engine.close());
        await engine.initialize();

        final cors = engine.config.security.cors;
        expect(cors.enabled, isTrue);
        expect(cors.allowedOrigins, equals(['https://app.dev']));
        expect(cors.allowedMethods, equals(['GET', 'POST']));
        expect(cors.allowedHeaders, equals(['Authorization']));
        expect(cors.allowCredentials, isTrue);
        expect(cors.maxAge, equals(600));
        expect(cors.exposedHeaders, equals(['X-Token']));
      });

      test('withCors updates config and engine values', () async {
        final engine = testEngine(
          configItems: {
            'logging': {'enabled': false},
          },
          options: [
            withCors(
              enabled: true,
              allowedOrigins: ['https://foo.dev'],
              allowedMethods: ['GET', 'PATCH'],
              allowedHeaders: ['Content-Type'],
              allowCredentials: true,
              maxAge: 900,
              exposedHeaders: ['X-Custom'],
            ),
          ],
        );
        addTearDown(() async => await engine.close());
        await engine.initialize();

        expect(engine.appConfig.getBool('cors.enabled'), isTrue);
        expect(
          engine.appConfig.getStringListOrNull('cors.allowed_origins'),
          equals(['https://foo.dev']),
        );
        expect(
          engine.appConfig.getStringListOrNull('cors.allowed_methods'),
          equals(['GET', 'PATCH']),
        );
        expect(
          engine.appConfig.getStringListOrNull('cors.allowed_headers'),
          equals(['Content-Type']),
        );
        expect(engine.appConfig.getBool('cors.allow_credentials'), isTrue);
        expect(engine.appConfig.getInt('cors.max_age'), equals(900));
        expect(
          engine.appConfig.getStringListOrNull('cors.exposed_headers'),
          equals(['X-Custom']),
        );

        final cors = engine.config.security.cors;
        expect(cors.enabled, isTrue);
        expect(cors.allowedOrigins, equals(['https://foo.dev']));
        expect(cors.allowedMethods, equals(['GET', 'PATCH']));
        expect(cors.allowedHeaders, equals(['Content-Type']));
        expect(cors.allowCredentials, isTrue);
        expect(cors.maxAge, equals(900));
        expect(cors.exposedHeaders, equals(['X-Custom']));
      });
    });
  });

  group('Proxy Trust Tests', () {
    test('default configuration trusts all proxies', () async {
      final engine = testEngine(
        configItems: {
          'security': {
            'trusted_proxies': {
              'enabled': true,
              'forward_client_ip': true,
              'proxies': ['0.0.0.0/0', '::/0'],
              'headers': ['X-Forwarded-For'],
            },
          },
        },
      );
      engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

      client = TestClient(
        RoutedRequestHandler(engine),
        options: TransportOptions(
          remoteAddress: InternetAddress('192.168.1.2'),
        ),
      );

      final response = await client.get(
        '/ip',
        headers: {
          'X-Forwarded-For': ['1.2.3.4'],
        },
      );
      response.assertBodyEquals('1.2.3.4');
    });

    test('restricted proxy list only trusts specified IPs', () async {
      final engine = testEngine(
        configItems: {
          'security': {
            'trusted_proxies': {
              'enabled': true,
              'forward_client_ip': true,
              'proxies': ['10.0.0.0/8'],
              'headers': ['X-Forwarded-For'],
            },
          },
        },
      );
      engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

      client = TestClient(
        RoutedRequestHandler(engine),
        options: TransportOptions(remoteAddress: InternetAddress('10.0.0.2')),
      );

      final response = await client.get(
        '/ip',
        headers: {
          'X-Forwarded-For': ['1.2.3.4'],
        },
      );
      response.assertBodyEquals('1.2.3.4');
    });

    test('untrusted proxy returns immediate client IP', () async {
      final engine = testEngine(
        configItems: {
          'security': {
            'trusted_proxies': {
              'enabled': true,
              'forward_client_ip': true,
              'proxies': ['10.0.0.0/8'],
              'headers': ['X-Forwarded-For'],
            },
          },
        },
      );
      engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

      client = TestClient(
        RoutedRequestHandler(engine),
        options: TransportOptions(
          remoteAddress: InternetAddress('192.168.1.2'),
        ),
      );

      final response = await client.get(
        '/ip',
        headers: {
          'X-Forwarded-For': ['1.2.3.4'],
        },
      );
      response.assertBodyEquals('192.168.1.2');
    });

    test('trusted platform headers take precedence', () async {
      final engine = testEngine(
        configItems: {
          'security': {
            'trusted_proxies': {
              'enabled': true,
              'forward_client_ip': true,
              'proxies': ['10.0.0.0/8'],
              'headers': ['X-Forwarded-For'],
              'platform_header': 'CF-Connecting-IP',
            },
          },
        },
      );
      engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

      client = TestClient(
        RoutedRequestHandler(engine),
        options: TransportOptions(remoteAddress: InternetAddress('10.0.0.2')),
      );

      final response = await client.get(
        '/ip',
        headers: {
          'CF-Connecting-IP': ['2.2.2.2'],
          'X-Forwarded-For': ['1.1.1.1'],
        },
      );
      response.assertBodyEquals('2.2.2.2');
    });

    test('header order is respected', () async {
      final engine = testEngine(
        configItems: {
          'security': {
            'trusted_proxies': {
              'enabled': true,
              'forward_client_ip': true,
              'proxies': ['0.0.0.0/0'],
              'headers': ['X-Real-IP', 'X-Forwarded-For'],
            },
          },
        },
      );
      engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

      client = TestClient(
        RoutedRequestHandler(engine),
        options: TransportOptions(remoteAddress: InternetAddress('10.0.0.2')),
      );

      final response = await client.get(
        '/ip',
        headers: {
          'X-Real-IP': ['5.5.5.5'],
          'X-Forwarded-For': ['1.1.1.1'],
        },
      );
      response.assertBodyEquals('5.5.5.5');
    });
  });

  group('Engine options', () {
    test('withMaxRequestSize updates security config', () {
      final engine = testEngine(options: [withMaxRequestSize(2048)]);
      expect(
        engine.appConfig.getInt('security.max_request_size'),
        equals(2048),
      );
    });
  });

  group('Request handling utilities', () {
    late Engine engine;
    late TestClient client;

    setUp(() {
      engine = testEngine();
      client = TestClient(RoutedRequestHandler(engine));
    });

    tearDown(() async {
      await client.close();
    });

    test('active requests are tracked during execution', () async {
      engine.get('/active', (ctx) async {
        final count = ctx.engine!.activeRequestCount;
        final sameRequest = identical(
          ctx.engine!.getRequest(ctx.request.id),
          ctx.request,
        );
        return ctx.json({'count': count, 'same': sameRequest});
      });

      final response = await client.get('/active');
      response.assertStatus(200);
      expect(response.json(), equals({'count': 1, 'same': true}));
      expect(engine.activeRequestCount, equals(0));
    });

    test('request size limits return 413 when exceeded', () async {
      engine =
          testEngine(
            configItems: {
              'security': {'max_request_size': 8},
            },
          )..post('/echo', (ctx) async {
            final body = await ctx.request.body();
            return ctx.string(body);
          });

      await client.close();
      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.post('/echo', '0123456789');
      response.assertStatus(HttpStatus.requestEntityTooLarge);
    });

    test('request size limits can be disabled with zero', () async {
      engine =
          testEngine(
            configItems: {
              'security': {'max_request_size': 0},
            },
          )..post('/echo', (ctx) async {
            final body = await ctx.request.body();
            return ctx.string(body);
          });

      await client.close();
      client = TestClient(RoutedRequestHandler(engine));

      final payload = List.filled(1024 * 64, 'x').join();
      final response = await client.post('/echo', payload);
      response
        ..assertStatus(200)
        ..assertBodyEquals(payload);
    });
  });

  test('withTrustedProxies updates security config', () {
    final engine = testEngine();
    withTrustedProxies(['10.0.0.0/8'])(engine);

    final proxies = engine.appConfig.getStringListOrNull(
      'security.trusted_proxies.proxies',
    );
    expect(proxies, contains('10.0.0.0/8'));
  });

  test('trusted platform can be configured via security config', () async {
    final engine = testEngine(
      configItems: {
        'security': {
          'trusted_proxies': {
            'enabled': true,
            'forward_client_ip': true,
            'proxies': ['0.0.0.0/0'],
            'platform_header': 'CF-Connecting-IP',
          },
        },
      },
    );
    engine.get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

    client = TestClient(
      RoutedRequestHandler(engine),
      options: TransportOptions(remoteAddress: InternetAddress('10.0.0.2')),
    );

    final response = await client.get(
      '/ip',
      headers: {
        'CF-Connecting-IP': ['9.9.9.9'],
        'X-Forwarded-For': ['8.8.8.8'],
      },
    );
    response.assertBodyEquals('9.9.9.9');
  });
}
