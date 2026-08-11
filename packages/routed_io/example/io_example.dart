import 'package:routed_core/routed_core.dart';
import 'package:routed_io/routed_io.dart';

/// Minimal smoke for native serve + portable edge.
Future<void> main() async {
  final engine = Engine(providers: Engine.defaultProviders);
  engine.get('/', (ctx) => ctx.string('io-ok'));
  engine.get('/portable', (ctx) => ctx.json({'edge': true}));
  await engine.initialize();

  // Portable path without binding (in-memory style via handlePortable).
  final portableOut = await engine.handlePortable(
    PortableRequest(
      method: 'GET',
      uri: Uri.parse('http://127.0.0.1/portable'),
      headers: PortableHeaders({
        'host': ['127.0.0.1'],
      }),
    ),
  );
  // ignore: avoid_print
  print('portable status=${portableOut.statusCode} body=${portableOut.bodyText}');

  // Live server (native fast path).
  final handle = await serveIo(engine, host: '127.0.0.1', port: 0, echo: false);
  // ignore: avoid_print
  print('listening on http://${handle.host}:${handle.port}');
  await handle.close();
}
