import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_class_view/shelf_class_view.dart';
import 'package:shelf_router/shelf_router.dart';

/// Simple view to test the response system
class TestView extends View {
  @override
  List<String> get allowedMethods => ['GET'];

  @override
  Future<void> get() async {
    // Test different response types
    final path = (await getUri()).path;

    switch (path) {
      case '/html':
        response().html(
          '<h1>HTML Response</h1><p>This is an HTML response!</p>',
        );
        break;
      case '/json':
        response().json({'message': 'JSON Response', 'success': true});
        break;
      case '/text':
        response().text('Plain text response');
        break;
      case '/redirect':
        response().redirect('/html');
        break;
      case '/status':
        response().status(201).json({'created': true});
        break;
      case '/headers':
        response()
            .header('X-Custom-Header', 'custom-value')
            .header('Cache-Control', 'max-age=3600')
            .json({'headers': 'set'});
        break;
      case '/view':
        response().view('test.html', {
          'title': 'Template Test',
          'message': 'This is a template test!',
          'items': ['Item 1', 'Item 2', 'Item 3'],
        });
        break;
      default:
        response().view('index.html', {
          'title': 'Laravel-Style Response Test',
          'endpoints': [
            '/html - HTML response',
            '/json - JSON response',
            '/text - Plain text response',
            '/redirect - Redirect to /html',
            '/status - JSON with 201 status',
            '/headers - JSON with custom headers',
            '/view - Template rendering test',
          ],
        });
    }
  }
}

Router setupRoutes() {
  final router = Router();

  // Test all the different response types
  router.getView('/', () => TestView());
  router.getView('/html', () => TestView());
  router.getView('/json', () => TestView());
  router.getView('/text', () => TestView());
  router.getView('/redirect', () => TestView());
  router.getView('/status', () => TestView());
  router.getView('/headers', () => TestView());
  router.getView('/view', () => TestView());

  return router;
}

void main() async {
  final router = setupRoutes();

  await io.serve(router.call, 'localhost', 8080);
  print('🚀 Laravel-Style Response Test Server');
  print('   Running on http://localhost:8080');
  print('');
  print('📝 Test endpoints:');
  print('  http://localhost:8080/        - Home page');
  print('  http://localhost:8080/html    - HTML response');
  print('  http://localhost:8080/json    - JSON response');
  print('  http://localhost:8080/text    - Text response');
  print('  http://localhost:8080/redirect - Redirect test');
  print('  http://localhost:8080/status   - Status code test');
  print('  http://localhost:8080/headers  - Custom headers test');
  print('  http://localhost:8080/view     - Template test');
}
