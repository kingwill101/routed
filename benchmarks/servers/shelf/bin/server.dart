import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8002;
  final host = Platform.environment['HOST'] ?? '0.0.0.0';

  final router = Router()
    ..get('/', (Request request) => Response.ok('ok'))
    ..get(
        '/json',
        (Request request) => Response.ok(
              jsonEncode({"ok": true}),
              headers: {HttpHeaders.contentTypeHeader: 'application/json'},
            ));

  final handler = const Pipeline().addHandler(router);

  final server = await shelf_io.serve(
    handler,
    host,
    port,
    shared: true,
  );

  // ignore: avoid_print
  print('shelf listening on http://${server.address.host}:${server.port}');
}
