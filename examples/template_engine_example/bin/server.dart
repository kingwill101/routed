import 'package:file/memory.dart';
import 'package:routed/routed.dart';

void main(List<String> args) async {
  final engine = Engine();
  final fs = MemoryFileSystem();

  // Create template files
  final templates = fs.directory('templates')..createSync();

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
  engine.useLiquid(directory: 'templates', fileSystem: fs);

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
