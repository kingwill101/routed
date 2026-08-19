import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

import 'test_engine.dart';

void main() {
  test(
    'typed core and routing configurations are independently addressable',
    () async {
      final engine = testEngine(
        config: EngineConfig(
          security: const EngineSecurityFeatures(
            maxRequestSize: 12 * 1024 * 1024,
            cors: CorsConfig(
              enabled: true,
              allowedOrigins: ['https://example.test'],
            ),
          ),
        ),
        routingConfig: const RoutingConfig(
          redirectTrailingSlash: false,
          handleMethodNotAllowed: true,
        ),
      );
      addTearDown(engine.close);

      await engine.initialize();

      expect(
        engine.typedConfig<EngineConfig>().security.maxRequestSize,
        12 * 1024 * 1024,
      );
      expect(
        engine.typedConfig<RoutingConfig>().redirectTrailingSlash,
        isFalse,
      );
      expect(engine.config.security.cors.enabled, isTrue);
    },
  );

  test('invalid typed configurations fail before provider boot', () async {
    final engine = testEngine(
      config: EngineConfig(
        security: const EngineSecurityFeatures(maxRequestSize: 0),
      ),
    );

    expect(engine.initialize, throwsA(isA<ConfigValidationException>()));
    await engine.close();
  });

  test('runtime configuration is fixed after initialization', () async {
    final engine = testEngine();
    await engine.initialize();
    addTearDown(engine.close);

    expect(() => engine.setRuntimeContext(RuntimeContext()), throwsStateError);
  });
}
