import 'package:routed/routed.dart';
import 'package:routed_storage/routed_storage.dart';

void main() async {
  final manager = StorageManager()
    ..registerDisk('local', LocalStorageDisk(root: '/tmp/storage'))
    ..setDefault('local');

  final engine = Engine();
  engine.get('/resolve/:path', (ctx) {
    final path = ctx.storageDisk().resolve(ctx.param('path')!);
    return ctx.json({'resolved': path});
  }, middlewares: [storageMiddleware(manager)]);

  print('routed_storage example: StorageManager with local disk');
  await engine.close();
}
