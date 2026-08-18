import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
  registerRoutedProviders();
  final engine = await Engine.create(
    providers: [
      CoreServiceProvider.withLoader(
        const ConfigLoaderOptions(
          configDirectory: 'config',
          loadEnvFiles: false,
          includeEnvironmentSubdirectory: false,
        ),
      ),
      RoutingServiceProvider(),
      ...Engine.builtins.where(
        (provider) =>
            provider is! CoreServiceProvider &&
            provider is! RoutingServiceProvider,
      ),
    ],
  );

  // Declarative static mounts are not part of the current provider bundle.
  // Register the supported direct helpers so this example serves real files.
  engine.static('/css', 'public/css');
  engine.static('/assets', 'public');

  engine.get('/', (ctx) async {
    return ctx.json({'message': 'Welcome to Static Mounts!'});
  });

  return engine;
}
