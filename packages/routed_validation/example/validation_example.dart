import 'dart:convert';

import 'package:routed_core/routed_core.dart';

void main() async {
  final engine = Engine()
    ..post('/users', (ctx) async {
      final body = await ctx.request.body();
      final data = body.isNotEmpty
          ? (jsonDecode(body) as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      return ctx.json({'data': data});
    });
  // Keep the example's startup message visible when it is run directly.
  // ignore: avoid_print
  print('routed_validation example: POST /users');
  await engine.close();
}
