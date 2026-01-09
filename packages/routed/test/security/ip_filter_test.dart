import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import '../test_engine.dart';

void main() {
  group('IP filter middleware', () {
    test('denies requests outside allow list', () async {
      final engine = testEngine(
        configItems: {
          'security': {
            'ip_filter': {
              'enabled': true,
              'default_action': 'deny',
              'allow': ['203.0.113.5'],
              'respect_trusted_proxies': false,
            },
          },
        },
      );
      addTearDown(() async => await engine.close());

      engine.get('/secure', (ctx) => ctx.string('ok'));
      await engine.initialize();

      final handler = RoutedRequestHandler(engine);
      final client = TestClient(handler, mode: TransportMode.ephemeralServer);
      addTearDown(() async => await client.close());

      final res = await client.get('/secure');
      expect(res.statusCode, equals(HttpStatus.forbidden));
    });

    test(
      'allows whitelisted forwarded addresses when respecting proxies',
      () async {
        final engine = testEngine(
          configItems: {
            'security': {
              'trusted_proxies': {
                'enabled': true,
                'forward_client_ip': true,
                'proxies': ['127.0.0.1/32'],
                'headers': ['X-Forwarded-For'],
              },
              'ip_filter': {
                'enabled': true,
                'default_action': 'deny',
                'allow': ['203.0.113.5'],
                'respect_trusted_proxies': true,
              },
            },
          },
        );
        addTearDown(() async => await engine.close());

        engine.get('/secure', (ctx) => ctx.string('ok'));
        await engine.initialize();

        final handler = RoutedRequestHandler(engine);
        final client = TestClient(handler, mode: TransportMode.ephemeralServer);
        addTearDown(() async => await client.close());

        final res = await client.get(
          '/secure',
          headers: {
            'X-Forwarded-For': ['203.0.113.5'],
          },
        );
        res.assertStatus(HttpStatus.ok).assertBodyEquals('ok');
      },
    );

    test('deny list takes precedence over allow list', () async {
      final engine = testEngine(
        configItems: {
          'security': {
            'ip_filter': {
              'enabled': true,
              'default_action': 'allow',
              'allow': ['0.0.0.0/0'],
              'deny': ['198.51.100.0/24'],
              'respect_trusted_proxies': true,
            },
            'trusted_proxies': {
              'enabled': true,
              'forward_client_ip': true,
              'proxies': ['127.0.0.1/32'],
              'headers': ['X-Forwarded-For'],
            },
          },
        },
      );
      addTearDown(() async => await engine.close());

      engine.get('/secure', (ctx) => ctx.string('ok'));
      await engine.initialize();

      final handler = RoutedRequestHandler(engine);
      final client = TestClient(handler, mode: TransportMode.ephemeralServer);
      addTearDown(() async => await client.close());

      final allowed = await client.get(
        '/secure',
        headers: {
          'X-Forwarded-For': ['203.0.113.200'],
        },
      );
      allowed.assertStatus(HttpStatus.ok).assertBodyEquals('ok');

      final denied = await client.get(
        '/secure',
        headers: {
          'X-Forwarded-For': ['198.51.100.25'],
        },
      );
      expect(denied.statusCode, equals(HttpStatus.forbidden));
    });
  });
}
