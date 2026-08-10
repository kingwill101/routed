import 'dart:convert';
import 'package:routed_core/routed_core.dart';

void main() async {
  final engine = Engine();
  engine.post('/users', (ctx) async {
    final body = await ctx.request.httpRequest.cast<List<int>>().transform(utf8.decoder).join();
    final data = body.isNotEmpty ? jsonDecode(body) : {};
    return ctx.json({'data': data});
  });
  print('routed_validation example: POST /users');
  await engine.close();
}
