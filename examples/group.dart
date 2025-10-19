// ignore_for_file: depend_on_referenced_packages

import 'package:routed/routed.dart';

final Engine engine = Engine();

void main() {
  Router v1 = Router(path: "/v1");

  addUserRoutes(v1);
  addPingRoutes(v1);

  Router v2 = Router(path: "/v2");
  addUserRoutes(v2);

  engine.use(v1);
  engine.use(v2);
  engine.serve(port: 8080);
}

void addPingRoutes(Router r) {
  r.group(
    path: "/ping",
    builder: (c) {
      c.get('/', (EngineContext context) {
        context.json({'message': 'pong'});
      });
    },
  );
}

void addUserRoutes(Router r) {
  r.group(
    path: "/users",
    builder: (c) {
      c.get('/', (EngineContext context) {
        context.string('users');
      });

      c.get('/comments', (EngineContext context) {
        context.string('users comments');
      });

      c.get('/pictures', (EngineContext context) {
        context.string('users pictures');
      });
    },
  );
}
