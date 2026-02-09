import 'package:routed/routed.dart';

import 'package:routed/providers.dart';
import 'inertia_views.dart';
import 'package:routed_inertia/routed_inertia.dart';

/// Simple in-memory todo store.
class TodoStore {
  int _nextId = 4;
  final List<Map<String, dynamic>> _todos = [
    {'id': 1, 'text': 'Learn Routed', 'done': true},
    {'id': 2, 'text': 'Build an Inertia app', 'done': true},
    {'id': 3, 'text': 'Add more pages', 'done': false},
  ];

  List<Map<String, dynamic>> all() =>
      _todos.map((t) => Map<String, dynamic>.from(t)).toList();

  void add(String text) {
    _todos.add({'id': _nextId++, 'text': text, 'done': false});
  }

  void toggle(int id) {
    final todo = _todos.firstWhere((t) => t['id'] == id, orElse: () => {});
    if (todo.isNotEmpty) {
      todo['done'] = !(todo['done'] as bool);
    }
  }

  void remove(int id) {
    _todos.removeWhere((t) => t['id'] == id);
  }
}

Future<Engine> createEngine({bool initialize = true}) async {
  registerRoutedInertiaProvider(ProviderRegistry.instance);

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

  configureInertiaViews(engine);

  final store = TodoStore();

  engine.get('/', (ctx) async {
    return ctx.inertia(
      'Home',
      props: {'title': 'Demo App', 'subtitle': 'Routed + Inertia starter'},
    );
  });

  // List todos
  engine.get('/todos', (ctx) async {
    return ctx.inertia(
      'Todos',
      props: {'title': 'Todos', 'todos': store.all()},
    );
  });

  // Create a todo
  engine.post('/todos', (ctx) async {
    final data = <String, dynamic>{};
    await ctx.bind(data);
    final text = (data['text'] as String?)?.trim() ?? '';
    if (text.isNotEmpty) {
      store.add(text);
    }
    return ctx.redirect('/todos');
  });

  // Toggle a todo's done state
  engine.put('/todos/{id}', (ctx) async {
    final id = int.tryParse(ctx.param('id') ?? '') ?? 0;
    store.toggle(id);
    return ctx.redirect('/todos');
  });

  // Delete a todo
  engine.delete('/todos/{id}', (ctx) async {
    final id = int.tryParse(ctx.param('id') ?? '') ?? 0;
    store.remove(id);
    return ctx.redirect('/todos');
  });

  return engine;
}
