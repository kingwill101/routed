// ignore_for_file: unnecessary_import

import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed_views/routed_views.dart';

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

  // Register the view engine so templates resolve through the manager.
  engine.container
      .get<ViewEngineManager>()
      .register(LiquidViewEngine(root: LiquidRoot(fileSystem: fs)));

  // Routes for Liquid templates
  engine.get('/liquid', (ctx) {
    ctx.template(
      templateName: 'welcome.liquid',
      data: {
        'user': {'name': 'User'},
        'show_preferences': true,
        'preferences': ['dark mode', 'notifications'],
      },
    );
  });

  await engine.serve(host: '127.0.0.1', port: 8080);
}
