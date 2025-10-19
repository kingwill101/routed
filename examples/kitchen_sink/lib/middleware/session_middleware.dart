import 'package:routed/routed.dart';

Future<Response> validateSession(EngineContext ctx, Next next) async {
  // if (userId == null) {
  //   return ctx.string('Unauthorized', statusCode: 401);
  // }
  return await next();
}
