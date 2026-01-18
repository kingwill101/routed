import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
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
    ],
  );

  engine.get('/', (ctx) async {
    return ctx.json({'message': 'Welcome to {{{routed:humanName}}}!'});
  });

  return engine;
}
