// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:routed/routed.dart';

Middleware cookieTool() {
  return (EngineContext ctx) async {
    final cookie = ctx.cookie("label");
    if (cookie == null) {
      ctx.json({"error": "Forbidden with no cookie"});
      ctx.abort();
    }
  };
}

void main() {
  final router1 = Router();

  router1.get('/login', (c) {
    c.setCookie("label", "hello",
        maxAge: 30, path: "/", sameSite: SameSite.none, secure: true);
    c.string("Login success");
  });

  router1.get('/home', (c) {
    c.json({"data": "Welcome to the home page"});
  }, middlewares: [cookieTool()]);
  Engine engine = Engine();
  engine.use(router1);
  engine.serve(port: 8080);
}
