import 'package:routed/routed.dart';

void main() async {
  final engine = Engine();

  // Configure Jinja template engine
  engine.useJinja(directory: 'templates');

  // Basic template with variables and loops
  engine.get('/hello', (ctx) {
    return ctx.html('hello.html', data: {
      'name': 'World',
      'showList': true,
      'items': [
        'Welcome to Jinja templating',
        'Try the extended template',
        'Or the dynamic data example'
      ]
    });
  });

  // Template inheritance example
  engine.get('/extended', (ctx) {
    return ctx.html('extended.html',
        data: {'name': 'Template User', 'showList': false});
  });

  // Dynamic data example
  engine.get('/data/:name', (ctx) {
    final name = ctx.param('name');
    return ctx.html('hello.html', data: {
      'name': name,
      'showList': true,
      'items': [
        'Welcome $name',
        'Current time: ${DateTime.now()}',
        'Your IP: ${ctx.request.ip}'
      ]
    });
  });

  // Start the server
  await engine.serve(port: 3000);
  print('Server running at http://localhost:3000');
  print('Try visiting:');
  print('  - http://localhost:3000/hello');
  print('  - http://localhost:3000/extended');
  print('  - http://localhost:3000/data/YourName');
}
