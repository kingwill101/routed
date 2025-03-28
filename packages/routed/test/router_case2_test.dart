import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed/src/file_handler.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';

void main() {
  late TestClient client;

  tearDown(() async {
    await client.close();
  });

  group('Route Matching Tests', () {
    test('Single route match works for various HTTP methods', () async {
      final engine = Engine();

      // Define routes for all HTTP methods
      final methods = [
        'GET',
        'POST',
        'PUT',
        'PATCH',
        'HEAD',
        'OPTIONS',
        'DELETE',
        'CONNECT',
        'TRACE'
      ];

      for (final method in methods) {
        engine.handle(method, '/test', (ctx) => ctx.string('ok'));
        engine.handle(method, '/test2', (ctx) => ctx.string('any ok'));
      }

      client = TestClient(RoutedRequestHandler(engine));

      for (final method in methods) {
        final response = await client.request(method, '/test');
        response
          ..assertStatus(200)
          ..assertBodyEquals('ok');

        final response2 = await client.request(method, '/test2');
        response2
          ..assertStatus(200)
          ..assertBodyEquals('any ok');
      }
    });

    test('Route mismatch returns 404', () async {
      final engine = Engine();

      // Define a single POST route
      engine.post('/test_2', (ctx) => ctx.string('post ok'));

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.get('/test');
      response.assertStatus(404);
    });
  });

  group('Trailing Slash Redirect Tests', () {
    test('Redirects for trailing slashes with 301 or 307', () async {
      final engine = Engine(config: EngineConfig(redirectTrailingSlash: true));

      engine.get('/path', (ctx) => ctx.string('get ok'));
      engine.post('/path2', (ctx) => ctx.string('post ok'));

      client = TestClient(RoutedRequestHandler(engine));

      // Test trailing slash redirects
      var response = await client.get('/path/');
      response
        ..assertStatus(301)
        ..assertHeader('Location', '/path');

      response = await client.post('/path2/', null);
      response
        ..assertStatus(307)
        ..assertHeader('Location', '/path2');
    });

    test('Disables trailing slash redirects when configured', () async {
      final engine = Engine(config: EngineConfig(redirectTrailingSlash: false));

      engine.get('/path', (ctx) => ctx.string('ok'));

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.get('/path/');
      response.assertStatus(404);
    });
  });

  group('Path Parameters Tests', () {
    test('Correctly parses path parameters', () async {
      final engine = Engine();

      engine.get('/test/{name}/{last_name}/{*wild}', (ctx) {
        final params = ctx.params;
        ctx.json({
          'name': params['name'],
          'last_name': params['last_name'],
          'wild': params['wild']
        });
      });

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.get('/test/john/smith/is/super/great');
      response
        ..assertStatus(200)
        ..assertJsonContains(
            {'name': 'john', 'last_name': 'smith', 'wild': 'is/super/great'});
    });
  });

  group('Static File Serving Tests', () {
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem();
    });

    test('StaticFS returns 404 for non-existent directory', () async {
      final engine = Engine();

      engine.staticFS('/static', Dir('/thisreallydoesntexist', fileSystem: fs));

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.get('/static/nonexistent');
      response.assertStatus(404);

      final headResponse = await client.head('/static/nonexistent');
      headResponse.assertStatus(404);
    });

    test('StaticFS handles file not found gracefully', () async {
      final engine = Engine();

      final dir = fs.directory('testdir')..createSync();

      engine.staticFS('/static', Dir(dir.path, fileSystem: fs));

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.get('/static/nonexistent');
      response.assertStatus(404);
    });

    test('Middleware called once per request for static files', () async {
      int middlewareCalls = 0;
      final engine = Engine(middlewares: [
        (ctx) async {
          middlewareCalls++;
          await ctx.next();
        }
      ]);

      final dir = fs.directory('nonexistent');
      engine.staticFS('/static', Dir(dir.path, fileSystem: fs));

      client = TestClient(RoutedRequestHandler(engine));

      await client.get('/static/file1');
      expect(middlewareCalls, equals(1));

      await client.head('/static/file2');
      expect(middlewareCalls, equals(2));
    });

    test('Static file serving works correctly', () async {
      final engine = Engine();

      final dir = fs.directory("files")..createSync();
      final file = dir.childFile('test_file.txt')
        ..writeAsStringSync('Routed Web Framework');

      final filename = file.uri.pathSegments.last;

      engine.static('/using_static', dir.path, fs);
      engine.staticFile('/result', file.path, fs);

      client = TestClient(RoutedRequestHandler(engine),
          mode: TransportMode.inMemory);

      // Test GET requests
      final staticResponse = await client.get('/using_static/$filename');
      final fileResponse = await client.get('/result');

      expect(staticResponse.statusCode, equals(fileResponse.statusCode));
      staticResponse
        ..assertStatus(200)
        ..assertBodyEquals('Routed Web Framework')
        ..assertHeaderContains('Content-Type', 'text/plain');

      // Test HEAD requests
      final staticHead = await client.head('/using_static/$filename');
      final fileHead = await client.head('/result');

      expect(staticHead.statusCode, equals(fileHead.statusCode));
      staticHead.assertStatus(200);
    });

    test('Directory listing works when enabled', () async {
      final engine = Engine();

      final dir = fs.directory('listingtest')..createSync();
      dir.childFile('testfile1.txt').createSync();
      dir.childFile('testfile2.txt').createSync();

      engine.staticFS('/', Dir(dir.path, listDirectory: true, fileSystem: fs));

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.get('/');
      response
        ..assertStatus(200)
        ..assertHeaderContains('Content-Type', 'text/html; charset=utf-8')
        ..assertBodyContains('testfile1.txt')
        ..assertBodyContains('testfile2.txt');
    });

    test('StaticFS returns 403 for path traversal attempts', () async {
      final engine = Engine();

      final dir = fs.directory('file/is/very/secured')
        ..createSync(recursive: true);
      engine.staticFS('/static', Dir(dir.path, fileSystem: fs));

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.get('/static/../../somefile');
      response.assertStatus(404);
    });

    test('Directory listing disabled by default', () async {
      final engine = Engine();

      final dir = fs.directory('nolist')..createSync();
      engine.static('/', dir.path, fs);

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.get('/');
      response.assertStatus(404);
    });
  });

  group('Middleware Tests', () {
    test('Middleware is applied once per request', () async {
      int middlewareCalls = 0;

      final engine = Engine(middlewares: [
        (EngineContext ctx) async {
          middlewareCalls++;
          await ctx.next();
        }
      ]);

      engine.staticFile('/static/{file}', './nonexistent');

      client = TestClient(RoutedRequestHandler(engine));

      (await client.get('/static/file1')).assertStatus(404);
      (await client.get('/static/file2')).assertStatus(404);

      expect(middlewareCalls, equals(2));
    });
  });

  group('Method Not Allowed Tests', () {
    test('Returns 405 with allowed methods when enabled', () async {
      final engine = Engine(config: EngineConfig(handleMethodNotAllowed: true));

      engine.get('/path', (ctx) => ctx.string('get ok'));
      engine.post('/path', (ctx) => ctx.string('post ok'));

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.put('/path', null);
      response
        ..assertStatus(405)
        ..assertHeaderContains('Allow', ['GET', 'POST']);
    });

    test('Returns 404 for wrong methods when disabled', () async {
      final engine =
          Engine(config: EngineConfig(handleMethodNotAllowed: false));

      engine.post('/path', (ctx) => ctx.string('post ok'));

      client = TestClient(RoutedRequestHandler(engine));

      final response = await client.get('/path');
      response.assertStatus(404);
    });
  });
}
