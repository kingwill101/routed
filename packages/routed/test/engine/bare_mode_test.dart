import 'dart:async';

import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:routed/validation.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  test('Engine() defaults to bare mode', () {
    final engine = Engine();

    expect(engine.container.has<Config>(), isFalse);
    expect(engine.container.has<EventManager>(), isFalse);
    expect(engine.container.has<RoutePatternRegistry>(), isTrue);
    expect(engine.container.has<ValidationRuleRegistry>(), isTrue);
    expect(engine.container.has<MiddlewareRegistry>(), isTrue);
    expect(engine.container.has<EngineConfig>(), isTrue);
  });

  test('Bare engine routes and middleware work', () async {
    final log = <String>[];

    FutureOr<Response> globalMw(EngineContext ctx, Next next) async {
      log.add('global');
      return await next();
    }

    FutureOr<Response> routeMw(EngineContext ctx, Next next) async {
      log.add('route');
      return await next();
    }

    final engine = Engine(middlewares: [globalMw]);
    engine.get('/users/{id}', (ctx) {
      log.add('handler');
      return ctx.string('user:${ctx.params['id']}');
    }, middlewares: [routeMw]);

    final client = TestClient.inMemory(RoutedRequestHandler(engine));
    addTearDown(() async {
      await client.close();
      await engine.close();
    });

    final response = await client.get('/users/42');
    response
      ..assertStatus(200)
      ..assertBodyEquals('user:42');

    expect(log, equals(['global', 'route', 'handler']));
  });

  test('Engine with providers boots providers', () async {
    final engine = Engine(
      providers: [CoreServiceProvider(), RoutingServiceProvider()],
    );
    addTearDown(() async {
      await engine.close();
    });

    await engine.initialize();

    expect(engine.container.has<Config>(), isTrue);
    expect(engine.container.has<EventManager>(), isTrue);
  });
}
