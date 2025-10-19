import 'package:routed/routed.dart' as routed;
import 'package:routed/src/config/registry.dart';
import 'package:routed/src/contracts/contracts.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:test/test.dart';

class PluginDefaultsProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    values: {
      'plugin': {'enabled': true},
    },
  );

  @override
  void register(Container container) {}
}

class AuditDefaultsProvider extends ServiceProvider with ProvidesDefaultConfig {
  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    values: {
      'audit': {'enabled': true},
    },
  );

  @override
  void register(Container container) {}
}

void main() {
  test('registry aggregates defaults and applies missing keys', () async {
    final engine = routed.Engine(configItems: {'plugin.enabled': false});

    engine.registerProvider(PluginDefaultsProvider());

    await engine.initialize();

    final config = await engine.make<Config>();
    final registry = await engine.make<ConfigRegistry>();

    expect(config.get('plugin.enabled'), isFalse);
    expect(
      registry.combinedDefaults()['plugin'],
      containsPair('enabled', true),
    );

    engine.registerProvider(AuditDefaultsProvider());

    expect(config.get('audit.enabled'), isTrue);
  });
}
