import 'package:routed/routed.dart';
import 'package:routed/src/middleware/timeout.dart';

Middleware test1() {
  return (EngineContext ctx, Next next) async {
    print("test1");
    return await next();
  };
}

Middleware test2() {
  return (EngineContext ctx, Next next) async {
    print("test2");
    return await next();
  };
}

Middleware test3() {
  return (EngineContext ctx, Next next) async {
    print("test3");
    return await next();
  };
}

Future<Response> root(EngineContext c) async {
  print("sleeping");
  await Future<void>.delayed(const Duration(seconds: 3));
  print("woke up");
  return c.string('Hello from router1');
}

Response root2(EngineContext c) {
  final name = c.param("name");
  return c.string('Hello $name');
}

void main() {
  final router1 = Router();
  router1.get('/', root);
  router1.get('/{name:string}', root2);
  Engine engine = Engine(
    middlewares: [timeoutMiddleware(const Duration(seconds: 1))],
  );
  engine
      .use(prefix: '/api', router1, middlewares: [test1(), test2(), test3()])
      .serve(port: 8080);
}
