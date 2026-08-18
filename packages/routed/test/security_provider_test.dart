import 'dart:convert';

import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  test('security provider applies trusted proxy configuration', () async {
    registerRoutedProviders();
    expect(Engine.builtins.whereType<RoutedSecurityProvider>(), hasLength(1));
    final engine = Engine(
      configItems: {
        'security': {
          'trusted_proxies': {
            'enabled': true,
            'forward_client_ip': true,
            'proxies': ['127.0.0.1/32'],
            'headers': ['X-Forwarded-For'],
          },
        },
      },
      providers: [...Engine.defaultProviders, RoutedSecurityProvider()],
    )..get('/ip', (ctx) => ctx.string(ctx.request.clientIP));

    addTearDown(engine.close);

    await engine.initialize();
    expect(engine.config.features.enableProxySupport, isTrue);
    expect(engine.config.forwardedByClientIP, isTrue);

    final response = await engine.handlePortable(
      PortableRequest(
        method: 'GET',
        uri: Uri.parse('http://localhost/ip'),
        remoteAddress: '127.0.0.1',
        headers: PortableHeaders({
          'X-Forwarded-For': ['203.0.113.5'],
        }),
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(utf8.decode(response.bodyBytes ?? const []), '203.0.113.5');
    expect(engine.container.has<TrustedProxyResolver>(), isTrue);
  });

  test('security provider denies IPs outside the allow list', () async {
    registerRoutedProviders();
    final engine = Engine(
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
      providers: [...Engine.defaultProviders, RoutedSecurityProvider()],
    )..get('/secure', (ctx) => ctx.string('ok'));

    addTearDown(engine.close);

    await engine.initialize();
    expect(engine.middlewares, isNotEmpty);

    final response = await engine.handlePortable(
      PortableRequest(
        method: 'GET',
        uri: Uri.parse('http://localhost/secure'),
        remoteAddress: '127.0.0.1',
      ),
    );

    expect(response.statusCode, HttpStatus.forbidden);
  });

  test('batteries-included engine applies configured CORS', () async {
    final engine = await Engine.create(
      configItems: {
        'cors': {
          'enabled': true,
          'allowed_origins': ['https://app.example'],
          'allowed_methods': ['GET'],
        },
      },
    );
    addTearDown(engine.close);
    var handled = false;
    engine.get('/items', (ctx) {
      handled = true;
      return ctx.string('ok');
    });

    final response = await engine.handlePortable(
      PortableRequest(
        method: 'GET',
        uri: Uri.parse('https://api.example/items'),
        headers: PortableHeaders({
          'Origin': ['https://app.example'],
        }),
      ),
    );

    expect(handled, isTrue);
    expect(response.statusCode, HttpStatus.ok);
    expect(
      response.headers.get('Access-Control-Allow-Origin'),
      'https://app.example',
    );
  });

  test('CORS configuration reload updates the middleware', () async {
    final engine = await Engine.create(
      configItems: {
        'cors': {'enabled': false},
      },
    );
    addTearDown(engine.close);
    engine.get('/items', (ctx) => ctx.string('ok'));

    final before = await engine.handlePortable(
      PortableRequest(
        method: 'GET',
        uri: Uri.parse('https://api.example/items'),
        headers: PortableHeaders({
          'Origin': ['https://app.example'],
        }),
      ),
    );
    expect(before.headers.get('Access-Control-Allow-Origin'), isNull);

    final override = ConfigImpl()..merge(engine.appConfig.all());
    override.set('cors', {
      'enabled': true,
      'allowed_origins': ['https://app.example'],
    });
    await engine.replaceConfig(override);

    final after = await engine.handlePortable(
      PortableRequest(
        method: 'GET',
        uri: Uri.parse('https://api.example/items'),
        headers: PortableHeaders({
          'Origin': ['https://app.example'],
        }),
      ),
    );
    expect(
      after.headers.get('Access-Control-Allow-Origin'),
      'https://app.example',
    );
  });
}
