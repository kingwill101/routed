import 'package:routed/routed.dart';

Future<Response> validateApiKey(EngineContext ctx, Next next) async {
  final apiKey = ctx.requestHeader('X-API-Key');
  if (apiKey != 'YOUR_API_KEY') {
    return ctx.string('Unauthorized', statusCode: 401);
  }
  return await next();
}
