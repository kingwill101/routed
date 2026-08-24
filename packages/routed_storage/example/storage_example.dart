import 'package:routed_core/routed_core.dart';
import 'package:routed_storage/routed_storage.dart';

void main() async {
  final manager = StorageManager()
    ..registerDisk('local', LocalStorageDisk(root: '/tmp/storage'))
    ..setDefault('local');

  final engine = Engine()
    ..get('/resolve/:path', (ctx) {
      final path = ctx.storageDisk().resolve(ctx.param('path')!);
      return ctx.json({'resolved': path});
    }, middlewares: [storageMiddleware(manager)]);

  // Keep the example's startup message visible when it is run directly.
  // ignore: avoid_print
  print('routed_storage example: StorageManager with local disk');
  await engine.close();
}
