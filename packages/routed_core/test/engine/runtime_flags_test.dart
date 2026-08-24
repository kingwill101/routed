import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'runtime environment is available during typed configuration boot',
    () async {
      final engine = Engine(
        runtime: RuntimeContext(
          environment: RuntimeEnvironment({'APP_ENV': 'test'}),
        ),
        providers: [CoreServiceProvider(), RoutingServiceProvider()],
      );
      addTearDown(engine.close);

      await engine.initialize();

      expect(engine.configStore, isNotNull);
      expect(engine.configStore.get<EngineConfig>(), isA<EngineConfig>());
    },
  );

  test('bare engines do not expose application configuration', () async {
    final engine = Engine();
    addTearDown(engine.close);

    expect(engine.container.has<ConfigStore>(), isFalse);
  });
}
