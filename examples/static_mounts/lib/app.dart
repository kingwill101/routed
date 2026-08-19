import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
  final providers =
      Engine.builtins
          .where((provider) => provider is! RoutedStorageProvider)
          .toList()
        ..add(
          RoutedStorageProvider(
            configuration: StorageConfig(
              disks: {
                'local': const LocalStorageDiskConfig(root: 'storage/app'),
                'assets': const LocalStorageDiskConfig(root: 'public'),
              },
            ),
          ),
        );
  final engine = await Engine.create(providers: providers);

  // Declarative static mounts are not part of the current provider bundle.
  // Register the supported direct helpers so this example serves real files.
  engine.static('/css', 'public/css');
  engine.static('/assets', 'public');

  engine.get('/', (ctx) async {
    return ctx.json({'message': 'Welcome to Static Mounts!'});
  });

  return engine;
}
