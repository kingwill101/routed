import 'package:routed_core/routed_core.dart';
import 'dart:convert';

void main() async {
  final engine = Engine();
  engine.post('/users', (ctx) async {
    final body = await ctx.request.body();
    final data = body.isNotEmpty ? jsonDecode(body) : {};
    return ctx.json({'data': data});
  });
  print('routed_validation example: POST /users');
  await engine.close();
}
