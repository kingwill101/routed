import 'dart:convert';

import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  test('security provider applies trusted proxy configuration', () async {
    registerRoutedProviders();
    expect(Engine.builtins.whereType<RoutedSecurityProvider>(), hasLength(1));
    final engine = Engine(
      providers: [
        ...Engine.defaultProviders,
        RoutedSecurityProvider(
          RoutedSecurityConfig(
            trustedProxies: TrustedProxyConfig(
              enabled: true,
              forwardClientIp: true,
              proxies: ['127.0.0.1/32'],
              headers: ['X-Forwarded-For'],
            ),
          ),
        ),
      ],
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
      providers: [
        ...Engine.defaultProviders,
        RoutedSecurityProvider(
          RoutedSecurityConfig(
            ipFilter: IpFilterConfig(
              enabled: true,
              defaultAction: IpFilterAction.deny,
              allow: ['203.0.113.5'],
              respectTrustedProxies: false,
            ),
          ),
        ),
      ],
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
      providers: [
        ...Engine.defaultProviders,
        RoutedSecurityProvider(
          RoutedSecurityConfig(
            cors: CorsConfig(
              enabled: true,
              allowedOrigins: ['https://app.example'],
              allowedMethods: ['GET'],
            ),
          ),
        ),
      ],
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

  test('security configuration rejects invalid network values before boot', () {
    final future = Engine.create(
      providers: [
        ...Engine.defaultProviders,
        RoutedSecurityProvider(
          RoutedSecurityConfig(ipFilter: IpFilterConfig(allow: ['not-an-ip'])),
        ),
      ],
    );
    return expectLater(future, throwsA(isA<ConfigValidationException>()));
  });
}
