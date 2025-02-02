import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed/src/engine/engine_template.dart';

void main(List<String> args) async {
  final engine = Engine();
  final fs = MemoryFileSystem();

  // Create template files
  final templates = fs.directory('templates')..createSync();

  // Create Jinja template
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

  // Create extended template
  templates.childFile('extended.html').writeAsStringSync('''
    {% extends "hello.html" %}
    {% block content %}
      <p>Extended content here</p>
    {% endblock %}
  ''');

  // Configure Jinja template engine
  engine.useJinja(directory: 'templates', fileSystem: fs);

  // Routes for template rendering
  engine.get('/hello', (ctx) {
    ctx.html('hello.html', data: {
      'name': 'World',
      'showList': true,
      'items': ['One', 'Two', 'Three']
    });
  });

  engine.get('/extended', (ctx) {
    ctx.html('extended.html', data: {
      'name': 'World',
      'showList': true,
      'items': ['Four', 'Five', 'Six']
    });
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
