/// Minimal one-file example. Prefer the full sample project:
///
/// ```bash
/// cd example/api && dart pub get && dart run bin/smoke.dart
/// ```
///
/// See [example/api/README.md](api/README.md).
library;

import 'package:routed_core/routed_core.dart';

Future<void> main() async {
  final engine = Engine(providers: Engine.defaultProviders);
  engine.get('/health', (ctx) => ctx.json({'ok': true}));
  await engine.initialize();

  final out = await engine.handlePortable(
    PortableRequest(
      method: 'GET',
      uri: Uri.parse('http://127.0.0.1/health'),
      headers: PortableHeaders({
        'host': ['127.0.0.1'],
      }),
    ),
  );
  // ignore: avoid_print
  print('status=${out.statusCode} body=${out.bodyText}');
  // ignore: avoid_print
  print('Full sample: packages/routed_node/example/api');
}
