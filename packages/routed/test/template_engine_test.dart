import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  TestClient? client;
  late MemoryFileSystem fs;
  setUp(() {
    fs = MemoryFileSystem();
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

  tearDown(() async {
    await client?.close();
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

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/hello');
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

      client = TestClient(RoutedRequestHandler(engine));
      final response = await client!.get('/partial');
      response
        ..assertStatus(200)
        ..assertBodyContains('Custom Footer');
    });
  });
}
