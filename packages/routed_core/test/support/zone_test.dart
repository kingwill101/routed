import 'package:routed_core/src/engine/engine.dart';
import 'package:routed_core/src/engine/config.dart';
import 'package:routed_core/src/support/helpers.dart';
import 'package:routed_core/src/support/zone.dart';
import 'package:test/test.dart';
import '../test_engine.dart';

void main() {
  group('Zone Helpers', () {
    late Engine engine;

    setUp(() {
      engine = testEngine(
        providers: Engine.defaultProviders,
        config: EngineConfig(),
      );

      // Add some test routes
      engine.get('/users/{id}', (ctx) => null).name('users.show');
      engine.get('/posts/{slug}', (ctx) => null).name('posts.show');
    });

    test(
      'typed configuration helper returns values from current zone',
      () async {
        await engine.initialize();
        await AppZone.run(
          engine: engine,
          body: () async {
            expect(
              config<EngineConfig>(),
              same(engine.configStore.get<EngineConfig>()),
            );
            expect(
              AppZone.configuration.get<EngineConfig>(),
              isA<EngineConfig>(),
            );
          },
        );
      },
    );

    test('route helper generates URLs from current zone', () async {
      await AppZone.run(
        engine: engine,
        body: () async {
          expect(route('users.show', {'id': '123'}), equals('/users/123'));
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
          expect(() => route('non.existent'), throwsA(isA<Exception>()));
        },
      );
    });

    test('accessing helpers outside zone throws error', () {
      expect(() => config<EngineConfig>(), throwsStateError);
      expect(() => route('users.show'), throwsStateError);
    });
  });
}
