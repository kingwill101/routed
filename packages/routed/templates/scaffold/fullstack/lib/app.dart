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

  final todos = <Map<String, dynamic>>[
    {'id': 1, 'title': 'Ship Routed starter', 'completed': false},
  ];

  engine.group(
    path: '/api',
    builder: (router) {
      router.get('/todos', (ctx) async => ctx.json({'data': todos}));

      router.patch('/todos/{id}', (ctx) async {
        final id = ctx.mustGetParam<String>('id');
        final todo = await ctx.fetchOr404(
          () async => todos.firstWhere(
            (item) => item['id'].toString() == id,
            orElse: () => null,
          ),
          message: 'Todo not found',
        );

        final payload = Map<String, dynamic>.from(
          await ctx.bindJSON({}) as Map? ?? const {},
        );
        todo['completed'] = payload['completed'] ?? todo['completed'];
        todo['title'] = payload['title'] ?? todo['title'];

        return ctx.json(todo);
      });
    },
  );

  engine.useViewEngine(LiquidViewEngine(directory: 'templates'));

  engine.get('/', (ctx) async {
    return ctx.template(
      templateName: 'todos.liquid',
      data: {'app_title': '{{{routed:humanName}}}'},
    );
  });

  return engine;
}
