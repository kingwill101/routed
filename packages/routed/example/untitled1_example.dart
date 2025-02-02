import 'package:routed/routed.dart';
import 'package:routed/src/middleware/timeout.dart';

Middleware test1() {
  return (EngineContext ctx) async {
    print("test1");
    await ctx.next();
  };
}

Middleware test2() {
  return (ctx) async {
    print("test2");
    await ctx.next();
  };
}

Middleware test3() {
  return (ctx) async {
    print("test3");
    await ctx.next();
  };
}

root(EngineContext c) async {
  print("sleeping");
  await Future.delayed(Duration(seconds: 3));
  print("woke up");
  c.string('Hello from router1');
}

root2(EngineContext c) async {
  final name = c.param("name");
  c.string('Hello $name');
}

void main() {
  final router1 = Router();
  router1.get('/', root);
  router1.get('/{name:string}', root2);
  Engine engine =
      Engine(middlewares: [timeoutMiddleware(Duration(seconds: 1))]);
  engine.use(
    prefix: '/api',
    router1,
    middlewares: [test1(), test2(), test3()],
  ).serve(port: 8080);
}
