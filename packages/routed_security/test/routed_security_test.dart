import 'package:routed_core/routed_core.dart';
import 'package:routed_security/routed_security.dart';
import 'package:test/test.dart';

void main() {
  test('exports available', () {
    expect(corsMiddleware, isNotNull);
  });

  test('adds CORS headers to an allowed request', () async {
    var handled = false;
    final engine =
        Engine(
          providers: Engine.defaultProviders,
          middlewares: [
            corsMiddleware(
              const CorsConfig(
                enabled: true,
                allowedOrigins: ['https://app.example'],
                allowCredentials: true,
                exposedHeaders: ['X-Request-ID'],
              ),
            ),
          ],
        )..get('/items', (ctx) {
          handled = true;
          return ctx.string('ok');
        });
    await engine.initialize();
    addTearDown(engine.close);

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
    expect(response.statusCode, 200);
    expect(
      response.headers.get('Access-Control-Allow-Origin'),
      'https://app.example',
    );
    expect(response.headers.get('Access-Control-Allow-Credentials'), 'true');
    expect(
      response.headers.get('Access-Control-Expose-Headers'),
      'X-Request-ID',
    );
    expect(response.headers.get('Vary'), 'Origin');
  });

  test('short-circuits an allowed preflight request', () async {
    var handled = false;
    final engine =
        Engine(
          providers: Engine.defaultProviders,
          middlewares: [
            corsMiddleware(
              const CorsConfig(
                enabled: true,
                allowedMethods: ['GET', 'POST'],
                allowedHeaders: ['Authorization', 'Content-Type'],
                maxAge: 600,
              ),
            ),
          ],
        )..post('/items', (ctx) {
          handled = true;
          return ctx.string('created');
        });
    await engine.initialize();
    addTearDown(engine.close);

    final response = await engine.handlePortable(
      PortableRequest(
        method: 'OPTIONS',
        uri: Uri.parse('https://api.example/items'),
        headers: PortableHeaders({
          'Origin': ['https://app.example'],
          'Access-Control-Request-Method': ['POST'],
          'Access-Control-Request-Headers': ['Authorization, Content-Type'],
        }),
      ),
    );

    expect(handled, isFalse);
    expect(response.statusCode, 204);
    expect(response.headers.get('Access-Control-Allow-Origin'), '*');
    expect(response.headers.get('Access-Control-Allow-Methods'), 'GET, POST');
    expect(
      response.headers.get('Access-Control-Allow-Headers'),
      'authorization, content-type',
    );
    expect(response.headers.get('Access-Control-Max-Age'), '600');
    expect(
      response.headers.get('Vary'),
      'Origin, Access-Control-Request-Method, Access-Control-Request-Headers',
    );
  });

  test('rejects a disallowed preflight request', () async {
    final engine = Engine(
      providers: Engine.defaultProviders,
      middlewares: [
        corsMiddleware(
          const CorsConfig(
            enabled: true,
            allowedOrigins: ['https://app.example'],
            allowedMethods: ['GET'],
          ),
        ),
      ],
    )..get('/items', (ctx) => ctx.string('ok'));
    await engine.initialize();
    addTearDown(engine.close);

    final response = await engine.handlePortable(
      PortableRequest(
        method: 'OPTIONS',
        uri: Uri.parse('https://api.example/items'),
        headers: PortableHeaders({
          'Origin': ['https://evil.example'],
          'Access-Control-Request-Method': ['GET'],
        }),
      ),
    );

    expect(response.statusCode, 403);
    expect(response.headers.get('Access-Control-Allow-Origin'), isNull);
  });
}
