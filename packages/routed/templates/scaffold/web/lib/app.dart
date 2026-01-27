import 'package:routed/routed.dart';

Future<Engine> createEngine({bool initialize = true}) async {
  final engine = Engine(
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

  if (initialize) {
    await engine.initialize();
  }

  engine.useViewEngine(LiquidViewEngine(directory: 'templates'));

  engine.static('/assets', 'public');

  final pages = <String, Map<String, String>>{
    'about': {
      'title': 'About',
      'body': 'Built with Routed and Liquid templates.',
    },
    'contact': {
      'title': 'Contact',
      'body': 'Update this copy to match your project.',
    },
  };

  List<Map<String, String>> buildNavigation() {
    return [
      {'slug': '/', 'title': 'Home'},
      for (final entry in pages.entries)
        {'slug': '/pages/${entry.key}', 'title': entry.value['title']!},
    ];
  }

  engine.get('/', (ctx) async {
    return ctx.template(
      templateName: 'home.liquid',
      data: {
        'app_title': '{{{routed:humanName}}}',
        'lead':
            'This starter renders HTML on the server and ships a static assets folder.',
        'pages': buildNavigation(),
      },
    );
  });

  engine.get('/pages/{slug}', (ctx) async {
    final slug = ctx.mustGetParam<String>('slug');
    final page = ctx.requireFound(
      pages[slug],
      message: 'Page "$slug" not found',
    );

    return ctx.template(
      templateName: 'page.liquid',
      data: {
        'app_title': '{{{routed:humanName}}}',
        'page': page,
        'pages': buildNavigation(),
      },
    );
  });

  return engine;
}
