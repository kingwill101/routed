// ignore_for_file: depend_on_referenced_packages

import 'package:routed/middlewares.dart';
import 'package:routed/routed.dart';

final Map<String, String> db = {};

void main() {
  final engine = Engine();

  // Ping test
  engine.get('/ping', (c) {
    c.string('pong');
  });
  engine.get('/search', (ctx) async {
    final data = <String, dynamic>{};
    final q = ctx.query("q");
    ctx.json(data);
  });
  // Get user value
  engine.get('/user/{name}', (c) {
    final user = c.param('name');
    final value = db[user];
    if (value != null) {
      c.json({'user': user, 'value': value});
    } else {
      c.json({'user': user, 'status': 'no value'});
    }
  });

  // Authorized group
  final authorized = Router();

  authorized.post('/admin', (EngineContext c) async {
    final user = c.mustGet<String>('user');
    Map<String, dynamic> body = {};
    await c.bindJSON(body);
    final value = body['value'];
    if (value != null) {
      db[user] = value;
      c.json({'status': 'ok'});
    } else {
      c.json({'error': 'Value is required'});
    }
  }, middlewares: [
    basicAuth({'foo': 'bar', 'manu': '123'})
  ]);
  engine.use(authorized);
  engine.serve(port: 8080);
}
