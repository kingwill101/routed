import 'package:http/http.dart' as http;
import 'package:routed/routed.dart';

Middleware routedForwardMiddleware() {
  return (EngineContext c, Next next) async {
    final forwardHeader = c.headers.value('forward');
    if (forwardHeader != null && forwardHeader == 'ok') {
      final client = http.Client();
      try {
        var req = http.Request(c.method, c.uri);
        c.headers.forEach((k, v) {
          req.headers.addAll({k: v.toString()});
        });
        final response = await client.send(req);

        return c.string(
          await response.stream.bytesToString(),
          statusCode: response.statusCode,
        );
      } finally {
        client.close();
      }
    }
    return await next();
  };
}

Future<Response> reverse(EngineContext context) async {
  var remote = Uri.parse('http://xxx.xxx.xxx');
  var client = http.Client();

  try {
    var proxyRequest = http.Request(context.method, remote);
    proxyRequest.headers.forEach((k, v) {
      proxyRequest.headers.addAll({k: v.toString()});
    });

    var response = await client.send(proxyRequest);

    return context.string(await response.stream.bytesToString());
  } finally {
    client.close();
  }
}
