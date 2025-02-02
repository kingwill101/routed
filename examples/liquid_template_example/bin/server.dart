import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed/src/engine/engine_template.dart';

void main(List<String> args) async {
  final engine = Engine();
  final fs = MemoryFileSystem();

  // Create template files
  final templates = fs.directory('templates')..createSync();

  // Create main template
  templates.childFile('main.liquid').writeAsStringSync('''
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
        {% render "footer" %}
      </body>
    </html>
  ''');

  // Create partial template
  templates.childFile('footer.liquid').writeAsStringSync('''
    <footer>
      <p>{{ footer_text }}</p>
    </footer>
  ''');

  // Configure Liquid template engine
  engine.useLiquid(directory: 'templates', fileSystem: fs);

  // Routes for template rendering
  engine.get('/welcome', (ctx) {
    ctx.html('main.liquid', data: {
      'user': {'name': 'John Doe'},
      'show_preferences': true,
      'preferences': ['dark mode', 'notifications'],
      'footer_text': 'Copyright 2024'
    });
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
