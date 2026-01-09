import 'package:routed/routed.dart' as routed;
import 'package:routed/src/config/registry.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:test/test.dart';
import '../test_engine.dart';

class PluginDefaultsProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    docs: [
      ConfigDocEntry(
        path: 'plugin.enabled',
        type: 'bool',
        description: 'Enables the plugin feature.',
        defaultValue: true,
      ),
    ],
  );

  @override
  void register(Container container) {}
}

class AuditDefaultsProvider extends ServiceProvider with ProvidesDefaultConfig {
  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    docs: [
      ConfigDocEntry(
        path: 'audit.enabled',
        type: 'bool',
        description: 'Enables audit logging.',
        defaultValue: true,
      ),
    ],
  );

  @override
  void register(Container container) {}
}

void main() {
  test('registry aggregates defaults and applies missing keys', () async {
    final engine = testEngine(configItems: {'plugin.enabled': false});

    engine.registerProvider(PluginDefaultsProvider());

    await engine.initialize();

    final config = await engine.make<Config>();
    final registry = await engine.make<ConfigRegistry>();

    expect(config.get<bool>('plugin.enabled'), isFalse);
    expect(
      registry.combinedDefaults()['plugin'],
      containsPair('enabled', true),
    );

    engine.registerProvider(AuditDefaultsProvider());

    expect(config.get<bool>('audit.enabled'), isTrue);
  });
}
