import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  TestClient? client;
  late MemoryFileSystem fs;
  setUp(() {
    fs = MemoryFileSystem();
    fs.directory('templates')
      ..createSync()
      ..childFile('hello.liquid').writeAsStringSync('''
        <!DOCTYPE html>
        <html>
          <body>
            <h1>Hello {{ name }}!</h1>
            {% if show_list %}
              <ul>
              {% for item in items %}
                <li>{{ item }}</li>
              {% endfor %}
              </ul>
            {% endif %}
            {% block content %}{% endblock %}
            
            {{footer_text}}
          </body>
        </html>
      ''')
      ..childFile('extended.liquid').writeAsStringSync('''
        {% layout "hello.liquid" %}
        {% block content %}
          <p>Extended content here</p>
        {% endblock %}
      ''');
  });

  tearDown(() async {
    await client?.close();
  });

  group('Liquid Template Tests', () {
    Engine createEngine() {
      final engine = Engine(
        configItems: {
          'storage': {
            'default': 'templates',
            'disks': {
              'templates': {
                'driver': 'local',
                'root': 'templates',
                'file_system': fs,
              },
            },
          },
          'view': {'engine': 'liquid', 'disk': 'templates', 'directory': ''},
        },
      );
      engine.useViewEngine(
        LiquidViewEngine(
          root: LiquidRoot(fileSystem: fs),
          directory: 'templates',
        ),
      );
      return engine;
    }

    test('Liquid renders variables and filters', () async {
      final engine = createEngine();
      engine.get('/hello', (ctx) async {
        await ctx.template(
          templateName: 'extended.liquid',
          data: {
            'name': 'World',
            'show_list': true,
            'items': ['one', 'two'],
            'footer_text': 'Page Footer',
          },
        );
        ctx.abort();
      });

      addTearDown(() async => await engine.close());
      await engine.initialize();

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/hello');
      response
        ..assertStatus(200)
        ..assertBodyContains('Hello World!')..assertBodyContains('<li>one</li>')
        ..assertBodyContains('Page Footer');
    });

    test('Liquid includes', () async {
      final engine = createEngine();
      engine.get('/partial', (ctx) async {
        await ctx.template(
          templateName: 'hello.liquid',
          data: {'name': 'World', 'footer_text': 'Custom Footer'},
        );
        ctx.abort();
      });

      addTearDown(() async => await engine.close());
      await engine.initialize();

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/partial');
      response
        ..assertStatus(200)
        ..assertBodyContains('Custom Footer');
    });
  });
}
