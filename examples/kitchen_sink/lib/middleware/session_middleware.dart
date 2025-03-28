import 'package:routed/routed.dart';

Future<void> validateSession(EngineContext ctx) async {
  // if (userId == null) {
  //   ctx.response
  //     ..statusCode = 401
  //     ..write('Unauthorized');
  //   return;
  // }
  await ctx.next();
}
