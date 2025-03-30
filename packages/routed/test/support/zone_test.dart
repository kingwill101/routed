import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/support/helpers.dart';
import 'package:routed/src/support/zone.dart';
import 'package:test/test.dart';

void main() {
  group('Zone Helpers', () {
    late Engine engine;

    setUp(() {
      // Create engine with mock config
      engine = Engine(
        configItems: {
          'app.name': 'Test App',
          'app.env': 'testing',
          'database.host': 'localhost',
        },
        config: EngineConfig(),
      );

      // Add some test routes
      engine.get('/users/{id}', (ctx) => null).name('users.show');
      engine.get('/posts/{slug}', (ctx) => null).name('posts.show');
    });

    test('config helper returns values from current zone', () async {
      await AppZone.run(
        engine: engine,
        body: () async {
          expect(config('app.name') as String, equals('Test App'));
          expect(config('app.env') as String, equals('testing'));
          expect(config('database.host') as String, equals('localhost'));
          expect(config('non.existent', 'default'), equals('default'));
        },
      );
    });

    test('route helper generates URLs from current zone', () async {
      await AppZone.run(
        engine: engine,
        body: () async {
          expect(
            route('users.show', {'id': '123'}),
            equals('/users/123'),
          );
          expect(
            route('posts.show', {'slug': 'hello-world'}),
            equals('/posts/hello-world'),
          );
        },
      );
    });

    test('route helper throws on non-existent route', () async {
      await AppZone.run(
        engine: engine,
        body: () async {
          expect(
            () => route('non.existent'),
            throwsA(isA<Exception>()),
          );
        },
      );
    });

    test('accessing helpers outside zone throws error', () {
      expect(() => config('app.name') as String, throwsStateError);
      expect(() => route('users.show'), throwsStateError);
    });
  });
}
