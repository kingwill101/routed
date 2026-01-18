import 'dart:convert';
import 'dart:io';

import 'package:relic/io_adapter.dart';
import 'package:relic/relic.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8007;
  final host = Platform.environment['HOST'] ?? '0.0.0.0';
  final address = host == 'localhost'
      ? InternetAddress.loopbackIPv4
      : (InternetAddress.tryParse(host) ?? InternetAddress.anyIPv4);

  final app = RelicApp()
    ..get('/', _ok)
    ..get('/json', _json);

  await app.serve(
    address: address,
    port: port,
    shared: true,
  );
}

Response _ok(Request request) {
  return Response.ok(
    body: Body.fromString('ok', mimeType: MimeType.plainText),
  );
}

Response _json(Request request) {
  return Response.ok(
    body: Body.fromString(
      jsonEncode({"ok": true}),
      mimeType: MimeType.json,
    ),
  );
}
