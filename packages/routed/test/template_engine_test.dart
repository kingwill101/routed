import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:test/test.dart';

void main() {
  late EngineTestClient client;
  late MemoryFileSystem fs;

  setUp(() {
    fs = MemoryFileSystem();
  });

  tearDown(() async {
    await client.close();
  });

  group('Jinja Template Tests', () {
    setUp(() {
      // Create Jinja template with its specific syntax
      final templates = fs.directory('templates')..createSync();
      templates.childFile('hello.html').writeAsStringSync('''
        <!DOCTYPE html>
        <html>
          <body>
            <h1>Hello {{ name }}!</h1>
            {% if showList %}
              <ul>
              {% for item in items %}
                <li>{{ item }}</li>
              {% endfor %}
              </ul>
            {% endif %}
            {% block content %}{% endblock %}
          </body>
        </html>
      ''');

      templates.childFile('extended.html').writeAsStringSync('''
        {% extends "hello.html" %}
        {% block content %}
          <p>Extended content here</p>
        {% endblock %}
      ''');
    });

    test('Jinja renders variables and loops', () async {
      final engine = Engine();
      engine.useJinja(directory: 'templates', fileSystem: fs);
      fs.currentDirectory = fs.directory("templates");
      engine.get('/hello', (ctx) {
        ctx.html('hello.html', data: {
          'name': 'World',
          'showList': true,
          'items': ['one', 'two', 'three']
        });
      });

      client = EngineTestClient(engine);
      final response = await client.get('/hello');
      response
        ..assertStatus(200)
        ..assertBodyContains('Hello World!')
        ..assertBodyContains('<li>one</li>');
    });

    test('Jinja template inheritance', () async {
      final engine = Engine();
      engine.useJinja(directory: 'templates', fileSystem: fs);

      engine.get('/extended', (ctx) {
        ctx.html('extended.html', data: {'name': 'World'});
      });

      client = EngineTestClient(engine);
      final response = await client.get('/extended');
      response
        ..assertStatus(200)
        ..assertBodyContains('Extended content here');
    });
  });

  group('Liquid Template Tests', () {
    setUp(() {
      // Create Liquid template with its specific syntax
      final templates = fs.directory('templates')..createSync();
      templates.childFile('hello.liquid').writeAsStringSync('''
        <!DOCTYPE html>
        <html>
          <body>
            <h1>Hello {{ name }}!</h1>
            {% if show_list %}
              <ul>
              {% for item in items %}
                <li>{{ item | upcase }}</li>
              {% endfor %}
              </ul>
            {% endif %}
            {% render "partial.liquid" with footer_text: footer_text %}
          </body>
        </html>
      ''');

      templates.childFile('partial.liquid').writeAsStringSync('''
        <footer>{{ footer_text }}</footer>
      ''');
    });

    test('Liquid renders variables and filters', () async {
      final engine = Engine();
      engine.useLiquid(directory: 'templates', fileSystem: fs);

      engine.get('/hello', (ctx) {
        ctx.html('hello.liquid', data: {
          'name': 'World',
          'show_list': true,
          'items': ['one', 'two'],
          'footer_text': 'Page Footer'
        });
      });

      client = EngineTestClient(engine);
      final response = await client.get('/hello');
      response
        ..assertStatus(200)
        ..assertBodyContains('Hello World!')
        ..assertBodyContains('<li>ONE</li>')
        ..assertBodyContains('Page Footer');
    });

    test('Liquid includes', () async {
      final engine = Engine();
      engine.useLiquid(directory: 'templates', fileSystem: fs);

      engine.get('/partial', (ctx) {
        ctx.html('hello.liquid',
            data: {'name': 'World', 'footer_text': 'Custom Footer'});
      });

      client = EngineTestClient(engine);
      final response = await client.get('/partial');
      response
        ..assertStatus(200)
        ..assertBodyContains('Custom Footer');
    });
  });
}
