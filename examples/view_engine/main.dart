import "package:file/local.dart" as local;
import 'package:routed/routed.dart';

void main() async {
  final config = EngineConfig(
    views: ViewConfig(viewPath: 'views', cache: true),
  );

  final engine = Engine(config: config);

  final fs = local.LocalFileSystem();
  fs.currentDirectory = '${fs.currentDirectory.path}/views';
  // Configure template engines
  engine.useViewEngine(LiquidViewEngine(root: LiquidRoot(fileSystem: fs)));

  // Define some example data
  final updates = [
    {'message': 'New feature released', 'date': '2024-03-15'},
    {'message': 'Bug fixes and improvements', 'date': '2024-03-14'},
    {'message': 'Documentation updated', 'date': '2024-03-13'},
  ];

  // Home page route
  engine.get('/', (ctx) async {
    await ctx.template(
      templateName: 'home.mustache',
      data: {
        'title': 'Home',
        'user': null, // Not logged in
        'updates': updates,
      },
    );
  });

  // User profile route (simulated logged-in state)
  engine.get('/profile', (ctx) async {
    await ctx.template(
      templateName: 'home.mustache',
      data: {
        'title': 'Profile',
        'user': {'name': 'John Doe', 'lastVisit': '2024-03-14 15:30'},
        'updates': updates,
      },
    );
  });

  // Start the server
  await engine.serve(port: 3000);
  print('View engine example running on http://localhost:3000');
}
