import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8001;
  final host = Platform.environment['HOST'] ?? '0.0.0.0';
  final server = await HttpServer.bind(
    host,
    port,
    shared: true,
  );

  server.listen((HttpRequest request) {
    final response = request.response;
    if (request.uri.path == '/json') {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({"ok": true}));
    } else {
      response.headers.contentType = ContentType.text;
      response.write('ok');
    }
    response.close();
  });

  // ignore: avoid_print
  print('dart_io listening on http://$host:$port');
}
