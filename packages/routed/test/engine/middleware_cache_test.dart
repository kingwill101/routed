import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  test('caches middleware chains and invalidates on changes', () {
    Future<Response> passThrough(EngineContext ctx, Next next) async {
      return await next();
    }

    final engine = Engine(middlewares: [passThrough]);
    engine.get('/hello', (ctx) => ctx.string('ok'));

    engine.allowedMethods('/hello');
    final initial = engine.debugEngineRoutes.singleWhere(
      (route) => route.path == '/hello',
    );
    expect(initial.cachedHandlers.length, equals(2));

    engine.addGlobalMiddleware(passThrough);
    engine.allowedMethods('/hello');
    final updated = engine.debugEngineRoutes.singleWhere(
      (route) => route.path == '/hello',
    );
    expect(updated.cachedHandlers.length, equals(3));
  });
}
