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
      </body>
    </html>
  ''');

  // Create Liquid template
  templates.childFile('welcome.liquid').writeAsStringSync('''
    <!DOCTYPE html>
    <html>
      <body>
        <h1>Welcome {{ user.name }}!</h1>
        {% if show_preferences %}
          <h2>Your Preferences:</h2>
          <ul>
          {% for pref in preferences %}
            <li>{{ pref | upcase }}</li>
          {% endfor %}
          </ul>
        {% endif %}
      </body>
    </html>
  ''');

  // Configure template engines
  engine.useJinja(directory: 'templates', fileSystem: fs);
  engine.useLiquid(directory: 'templates', fileSystem: fs);

  // Routes for Jinja templates
  engine.get('/jinja', (ctx) {
    ctx.html('hello.html', data: {
      'name': 'World',
      'showList': true,
      'items': ['One', 'Two', 'Three']
    });
  });

  // Routes for Liquid templates
  engine.get('/liquid', (ctx) {
    ctx.html('welcome.liquid', data: {
      'user': {'name': 'User'},
      'show_preferences': true,
      'preferences': ['dark mode', 'notifications']
    });
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
