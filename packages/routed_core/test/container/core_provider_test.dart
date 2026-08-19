import 'package:routed_core/routed_core.dart';
import 'package:test/test.dart';

import '../test_engine.dart';

void main() {
  test('publishes the typed engine configuration', () async {
    final configuration = EngineConfig(
      security: const EngineSecurityFeatures(maxRequestSize: 8 * 1024 * 1024),
    );
    final engine = testEngine(config: configuration);
    addTearDown(engine.close);

    await engine.initialize();

    expect(engine.config.security.maxRequestSize, 8 * 1024 * 1024);
    expect(
      engine.typedConfig<EngineConfig>().security.maxRequestSize,
      equals(configuration.security.maxRequestSize),
    );
    expect(
      engine.container.get<ConfigStore>().get<EngineConfig>(),
      isA<EngineConfig>(),
    );
    expect(engine.container.get<TrustedProxyResolver>(), isNotNull);
  });

  test('uses defaults without a YAML or dot-notation source', () async {
    final engine = testEngine();
    addTearDown(engine.close);

    await engine.initialize();

    expect(engine.config, isA<EngineConfig>());
    expect(engine.configStore.contains<EngineConfig>(), isTrue);
    expect(engine.container.has<ConfigStore>(), isTrue);
  });
}
