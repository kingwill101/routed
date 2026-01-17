import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
  final engine = await Engine.createFull(
    configOptions: const ConfigLoaderOptions(
      configDirectory: 'config',
      loadEnvFiles: false,
      includeEnvironmentSubdirectory: false,
    ),
  );

  engine.get('/', (ctx) async {
    return ctx.json({'message': 'Welcome to Static Mounts!'});
  });

  return engine;
}
