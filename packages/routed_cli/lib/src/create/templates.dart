import 'dart:convert';

typedef FileBuilder = String Function(TemplateContext context);

class TemplateContext {
  TemplateContext({required this.packageName, required this.humanName});

  final String packageName;
  final String humanName;
}

class ScaffoldTemplate {
  ScaffoldTemplate({
    required this.id,
    required this.description,
    required Map<String, FileBuilder> files,
    FileBuilder? readme,
    Map<String, String>? extraDependencies,
    Map<String, String>? extraDevDependencies,
  }) : fileBuilders = files,
       readmeBuilder = readme ?? _defaultReadme,
       extraDependencies = extraDependencies ?? const {},
       extraDevDependencies = extraDevDependencies ?? const {};

  final String id;
  final String description;
  final Map<String, FileBuilder> fileBuilders;
  final FileBuilder readmeBuilder;
  final Map<String, String> extraDependencies;
  final Map<String, String> extraDevDependencies;

  String renderReadme(TemplateContext context) => readmeBuilder(context);
}

class Templates {
  Templates._();

  static final Map<String, ScaffoldTemplate> _templates = {
    'basic': _buildBasicTemplate(),
    'api': _buildApiTemplate(),
    'web': _buildWebTemplate(),
    'fullstack': _buildFullstackTemplate(),
  };

  static ScaffoldTemplate resolve(String id) {
    final key = id.toLowerCase();
    final template = _templates[key];
    if (template == null) {
      throw ArgumentError('Unknown template "$id"');
    }
    return template;
  }

  static Iterable<ScaffoldTemplate> get all => _templates.values;

  static String describe() =>
      all.map((template) => '"${template.id}"').join(', ');
}

ScaffoldTemplate _buildBasicTemplate() {
  return ScaffoldTemplate(
    id: 'basic',
    description: 'Minimal JSON welcome route and config files.',
    files: {
      ..._commonFiles(),
      'lib/app.dart': (context) => _basicApp(context.humanName),
    },
    readme: (context) => _basicReadme(context.humanName),
  );
}

ScaffoldTemplate _buildApiTemplate() {
  return ScaffoldTemplate(
    id: 'api',
    description: 'JSON-first API skeleton with sample routes and tests.',
    files: {
      ..._commonFiles(),
      'lib/app.dart': _apiApp,
      'test/api_test.dart': _apiTest,
    },
    readme: _apiReadme,
    extraDevDependencies: const {'routed_testing': '^0.1.0'},
  );
}

ScaffoldTemplate _buildWebTemplate() {
  return ScaffoldTemplate(
    id: 'web',
    description: 'Server-rendered pages with HTML helpers.',
    files: {
      ..._commonFiles(),
      'lib/app.dart': _webApp,
      'templates/home.liquid': _webHomeTemplate,
      'templates/page.liquid': _webPageTemplate,
      'public/styles.css': _webStylesheet,
    },
    readme: _webReadme,
  );
}

ScaffoldTemplate _buildFullstackTemplate() {
  return ScaffoldTemplate(
    id: 'fullstack',
    description: 'Combined HTML + JSON starter, handy for SPAs or HTMX.',
    files: {
      ..._commonFiles(),
      'lib/app.dart': _fullstackApp,
      'test/api_test.dart': _fullstackApiTest,
    },
    readme: _fullstackReadme,
    extraDevDependencies: const {'routed_testing': '^0.1.0'},
  );
}

Map<String, FileBuilder> _commonFiles() {
  return {
    'bin/server.dart': (context) => _serverDart(context.packageName),
    'lib/commands.dart': (_) => _commandsEntry(),
    'tool/spec_manifest.dart': (context) =>
        _specManifestScript(context.packageName),
  };
}

String _basicApp(String humanName) {
  final message = humanName.isEmpty ? 'Routed' : humanName;
  return '''
import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
  final engine = await Engine.create();

  engine.get('/', (ctx) async {
    return ctx.json({'message': 'Welcome to $message!'});
  });

  return engine;
}
''';
}

String _basicReadme(String humanName) {
  return '''
# $humanName

A new [Routed](https://routed.dev) application.

## Getting started

```bash
dart pub get
dart run routed_cli dev
```

The default route responds with a friendly JSON payload. Edit
`lib/app.dart` to add additional routes, middleware, and providers.
''';
}

String _apiApp(TemplateContext context) {
  return '''
import 'dart:io';

import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
  final engine = await Engine.create();

  final users = <String, Map<String, dynamic>>{
    '1': {'id': '1', 'name': 'Ada Lovelace', 'email': 'ada@example.com'},
    '2': {'id': '2', 'name': 'Alan Turing', 'email': 'alan@example.com'},
  };

  engine.group(path: '/api/v1', builder: (router) {
    router.get('/health', (ctx) async {
      return ctx.json({'status': 'ok'});
    });

    router.get('/users', (ctx) async {
      return ctx.json({'data': users.values.toList()});
    });

    router.get('/users/:id', (ctx) async {
      final id = ctx.mustGetParam<String>('id');
      final user = await ctx.fetchOr404(
        () async => users[id],
        message: 'User not found',
      );
      return ctx.json(user);
    });

    router.post('/users', (ctx) async {
      final payload =
          await ctx.request.json() as Map<String, dynamic>? ?? {};
      final id = (users.length + 1).toString();
      final created = {
        'id': id,
        'name': payload['name'] ?? 'user-\$id',
        'email': payload['email'] ?? 'user\$id@example.com',
      };
      users[id] = created;
      return ctx.json(created, statusCode: HttpStatus.created);
    });
  });

  return engine;
}
''';
}

String _apiTest(TemplateContext context) {
  return '''
import 'package:routed_testing/routed_testing.dart';
import 'package:test/test.dart';

import 'package:${context.packageName}/app.dart' as app;

void main() {
  group('API', () {
    late TestClient client;

    setUpAll(() async {
      final engine = await app.createEngine();
      client = TestClient(RoutedRequestHandler(engine));
    });

    tearDownAll(() async {
      await client.close();
    });

    test('lists users', () async {
      final response = await client.get('/api/v1/users');
      response.assertStatus(200);
      response.expectJsonBody((json) {
        expect(json['data'], isA<List>());
      });
    });
  });
}
''';
}

String _apiReadme(TemplateContext context) {
  return '''
# ${context.humanName}

This project exposes a JSON API using [Routed](https://routed.dev).

## Useful scripts

```bash
dart pub get
```

```
# Run the API locally on port 8080
dart run routed_cli dev
```

### Example requests

```
curl http://localhost:8080/api/v1/health
curl http://localhost:8080/api/v1/users
```

See `lib/app.dart` for the complete route definitions. `test/api_test.dart`
shows how to exercise the engine with `routed_testing`.
''';
}

String _webApp(TemplateContext context) {
  return '''
import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
  final engine = await Engine.create();

  engine.useViewEngine(
    LiquidViewEngine(directory: 'templates'),
  );

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
        {'slug': '/pages/\${entry.key}', 'title': entry.value['title']!},
    ];
  }

  engine.get('/', (ctx) async {
    return ctx.template(
      templateName: 'home.liquid',
      data: {
        'app_title': '${context.humanName}',
        'lead':
            'This starter renders HTML on the server and ships a static assets folder.',
        'pages': buildNavigation(),
      },
    );
  });

  engine.get('/pages/:slug', (ctx) async {
    final slug = ctx.mustGetParam<String>('slug');
    final page = ctx.requireFound(
      pages[slug],
      message: 'Page "\$slug" not found',
    );

    return ctx.template(
      templateName: 'page.liquid',
      data: {
        'app_title': '${context.humanName}',
        'page': page,
        'pages': buildNavigation(),
      },
    );
  });

  return engine;
}
''';
}

String _webHomeTemplate(TemplateContext context) {
  return '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>{{ app_title }}</title>
    <link rel="stylesheet" href="/assets/styles.css" />
  </head>
  <body>
    <header>
      <h1>{{ app_title }}</h1>
      <p>{{ lead }}</p>
    </header>
    <nav>
      <ul class="nav">
        {% for item in pages %}
          <li><a href="{{ item.slug }}">{{ item.title }}</a></li>
        {% endfor %}
      </ul>
    </nav>
    <main>
      <section class="card">
        <h2>Customise your starter</h2>
        <p>Update <code>templates/home.liquid</code> to change this page.</p>
      </section>
    </main>
  </body>
</html>
''';
}

String _webPageTemplate(TemplateContext context) {
  return '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>{{ page.title }} - {{ app_title }}</title>
    <link rel="stylesheet" href="/assets/styles.css" />
  </head>
  <body>
    <header>
      <h1>{{ page.title }}</h1>
      <p class="lead">Served with Routed templates.</p>
    </header>
    <nav>
      <ul class="nav">
        {% for item in pages %}
          <li><a href="{{ item.slug }}">{{ item.title }}</a></li>
        {% endfor %}
      </ul>
    </nav>
    <main>
      <section class="card">
        <p>{{ page.body }}</p>
        <p class="note">Edit <code>templates/page.liquid</code> to customise this content.</p>
      </section>
    </main>
  </body>
</html>
''';
}

String _webStylesheet(TemplateContext context) {
  return '''
:root {
  color-scheme: light;
}

body {
  font-family: system-ui, sans-serif;
  margin: 2rem;
  background: #f8fafc;
  color: #1f2933;
}

header {
  margin-bottom: 1.5rem;
}

.lead {
  color: #475569;
}

.nav {
  list-style: none;
  padding: 0;
  display: flex;
  gap: 0.75rem;
}

.nav a {
  color: #2563eb;
  text-decoration: none;
  font-weight: 600;
}

.nav a:hover {
  text-decoration: underline;
}

main {
  max-width: 720px;
}

.card {
  background: #ffffff;
  border-radius: 0.5rem;
  padding: 1.5rem;
  box-shadow: 0 12px 30px -12px rgba(15, 23, 42, 0.35);
}

.note {
  margin-top: 1rem;
  font-style: italic;
  color: #64748b;
}
''';
}

String _webReadme(TemplateContext context) {
  return '''
# ${context.humanName}

Server-rendered pages powered by [Routed](https://routed.dev).

## Run locally

```bash
dart pub get
dart run routed_cli dev
```

Visit `http://localhost:8080` to see the landing page. Edit
`lib/app.dart` to customise HTML output or introduce templating.
''';
}

String _fullstackApp(TemplateContext context) {
  final sampleTodos = jsonEncode(<Map<String, dynamic>>[
    {'id': 1, 'title': 'Ship Routed starter', 'completed': false},
  ]);
  return """
import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';

Future<Engine> createEngine() async {
  final engine = await Engine.create();

  final todos = <Map<String, dynamic>>[
    {'id': 1, 'title': 'Ship Routed starter', 'completed': false},
  ];

  engine.group(path: '/api', builder: (router) {
    router.get('/todos', (ctx) async => ctx.json({'data': todos}));

    router.patch('/todos/:id', (ctx) async {
      final id = ctx.mustGetParam<String>('id');
      final todo = await ctx.fetchOr404(
        () async => todos.firstWhere(
          (item) => item['id'].toString() == id,
          orElse: () => null,
        ),
        message: 'Todo not found',
      );

      final payload = await ctx.request.json() as Map<String, dynamic>? ?? {};
      todo['completed'] = payload['completed'] ?? todo['completed'];
      todo['title'] = payload['title'] ?? todo['title'];

      return ctx.json(todo);
    });
  });

  engine.get('/', (ctx) async {
    return ctx.html('''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>${context.humanName}</title>
    <style>
      body { font-family: system-ui, sans-serif; margin: 2rem; }
      button { cursor: pointer; }
      li { margin-bottom: .5rem; }
    </style>
  </head>
  <body>
    <main>
      <h1>${context.humanName}</h1>
      <p>This page hydrates data from <code>/api/todos</code>.</p>
      <ul id="todo-list"></ul>
      <button id="toggle-first">Toggle first todo</button>
    </main>
    <script>
      const todos = $sampleTodos;

      async function refresh() {
        const response = await fetch('/api/todos');
        const json = await response.json();
        render(json.data);
      }

      function render(items) {
        const list = document.getElementById('todo-list');
        list.innerHTML = '';
        items.forEach((todo) => {
          const item = document.createElement('li');
          item.textContent = `\${todo.title} (\${todo.completed ? '✅' : '⬜️'})`;
          list.appendChild(item);
        });
      }

      document.getElementById('toggle-first').addEventListener('click', async () => {
        const response = await fetch('/api/todos/1', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ completed: true }),
        });
        if (response.ok) {
          await refresh();
        }
      });

      render(todos);
      refresh();
    </script>
  </body>
</html>
''');
  });

  return engine;
}
""";
}

String _fullstackApiTest(TemplateContext context) {
  return '''
import 'package:routed_testing/routed_testing.dart';
import 'package:test/test.dart';

import 'package:${context.packageName}/app.dart' as app;

void main() {
  test('GET /api/todos returns seeded data', () async {
    final engine = await app.createEngine();
    final client = TestClient(RoutedRequestHandler(engine));

    final response = await client.get('/api/todos');
    response.assertStatus(200);
    response.expectJsonBody((json) {
      expect(json['data'], isA<List>());
      expect(json['data'], isNotEmpty);
    });

    await client.close();
  });
}
''';
}

String _fullstackReadme(TemplateContext context) {
  return '''
# ${context.humanName}

A Routed starter that serves HTML and JSON in the same application.

## Commands

```bash
dart pub get
```

```
dart run routed_cli dev
```

- Visit http://localhost:8080 for the web UI.
- Call http://localhost:8080/api/todos for JSON responses.

The app renders vanilla HTML and exposes a simple REST API. Swap the front end
for HTMX, a SPA framework, or your favourite renderer while keeping the API layer
in Dart.
''';
}

String _serverDart(String packageName) {
  return '''
import 'package:$packageName/app.dart' as app;

Future<void> main(List<String> args) async {
  final engine = await app.createEngine();
  await engine.serve(host: '127.0.0.1', port: 8080);
}
''';
}

String _specManifestScript(String packageName) {
  return '''
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:$packageName/app.dart' as app;

Future<void> main(List<String> args) async {
  final engine = await app.createEngine();
  final manifest = engine.buildRouteManifest();
  stdout.writeln(manifest.toJsonString());
}
''';
}

String _defaultReadme(TemplateContext context) =>
    _basicReadme(context.humanName);

String _commandsEntry() {
  return '''
import 'dart:async';

import 'package:args/command_runner.dart';

FutureOr<List<Command<void>>> buildProjectCommands() {
  // Add project-specific CLI commands (for example, maintenance scripts) here.
  return const [];
}
''';
}
