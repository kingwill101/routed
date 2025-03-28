import 'package:routed/routed.dart';

Future<void> validateApiKey(EngineContext ctx) async {
  final apiKey = ctx.requestHeader('X-API-Key');
  if (apiKey != 'YOUR_API_KEY') {
    ctx.response
      ..statusCode = 401
      ..write('Unauthorized');
    return;
  }
  await ctx.next();
}
