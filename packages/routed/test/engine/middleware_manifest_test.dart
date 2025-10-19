import 'package:routed/routed.dart';
import 'package:routed/src/utils/deep_copy.dart';
import 'package:test/test.dart';

void main() {
  test(
    'manifest-derived middleware preserves order and removes duplicates',
    () async {
      final baseConfig = _baseConfig();
      final engine = Engine(
        includeDefaultProviders: false,
        providers: [_TestBootstrapProvider(baseConfig)],
      );

      engine.registerProvider(_ManifestProviderAlpha());
      engine.registerProvider(_ManifestProviderBeta());
      await engine.initialize();

      final registry = engine.container.get<ConfigRegistry>();
      final sources = registry.entries.map((entry) => entry.source).toList();
      expect(
        sources,
        containsAll(<String>['test.middleware.alpha', 'test.middleware.beta']),
      );

      expect(
        List<String>.from(engine.appConfig.get('http.providers') as List),
        equals(['test.middleware.alpha', 'test.middleware.beta']),
      );

      final globalIds = List<String>.from(
        engine.appConfig.get('http.middleware.global') as List,
      );
      expect(
        globalIds,
        equals([
          'user.global',
          'demo.global.alpha',
          'demo.global.shared',
          'demo.global.beta',
        ]),
      );
      expect(
        globalIds.where((id) => id == 'demo.global.shared').length,
        equals(1),
      );

      final groupMap = Map<String, dynamic>.from(
        engine.appConfig.get('http.middleware.groups') as Map,
      );
      expect(
        groupMap['web'],
        equals([
          'user.web',
          'demo.group.shared',
          'demo.group.alpha',
          'demo.group.beta',
        ]),
      );

      // When a middleware id lacks a registered factory it is skipped; only
      // provider-contributed ids should materialize in the configured stacks.
      expect(engine.middlewares.length, equals(3));
      expect(engine.middlewareGroup('web').length, equals(3));
    },
  );
}

Map<String, dynamic> _baseConfig() => {
  'app': {'name': 'Manifest Test'},
  'http': {
    'providers': ['test.middleware.alpha', 'test.middleware.beta'],
    'middleware': {
      'global': ['user.global'],
      'groups': {
        'web': ['user.web'],
      },
    },
  },
};

class _TestBootstrapProvider extends ServiceProvider {
  _TestBootstrapProvider(Map<String, dynamic> configItems)
    : _configItems = deepCopyMap(configItems);

  final Map<String, dynamic> _configItems;

  @override
  void register(Container container) {
    container.instance<EngineConfig>(EngineConfig());
    container.instance<MiddlewareRegistry>(MiddlewareRegistry());
    container.instance<Config>(ConfigImpl(_configItems));
  }
}

class _ManifestProviderAlpha extends ServiceProvider
    with ProvidesDefaultConfig {
  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    values: {
      'http': {
        'middleware_sources': {
          'test.middleware.alpha': {
            'global': ['demo.global.alpha', 'demo.global.shared'],
            'groups': {
              'web': ['demo.group.shared', 'demo.group.alpha'],
            },
          },
        },
      },
    },
  );

  @override
  String get configSource => 'test.middleware.alpha';

  @override
  void register(Container container) {
    final registry = container.get<MiddlewareRegistry>();
    registry.register(
      'demo.global.alpha',
      (_) =>
          (ctx, next) async => await next(),
    );
    registry.register(
      'demo.global.shared',
      (_) =>
          (ctx, next) async => await next(),
    );
    registry.register(
      'demo.group.shared',
      (_) =>
          (ctx, next) async => await next(),
    );
    registry.register(
      'demo.group.alpha',
      (_) =>
          (ctx, next) async => await next(),
    );
  }
}

class _ManifestProviderBeta extends ServiceProvider with ProvidesDefaultConfig {
  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    values: {
      'http': {
        'middleware_sources': {
          'test.middleware.beta': {
            'global': ['demo.global.shared', 'demo.global.beta'],
            'groups': {
              'web': ['demo.group.shared', 'demo.group.beta'],
            },
          },
        },
      },
    },
  );

  @override
  String get configSource => 'test.middleware.beta';

  @override
  void register(Container container) {
    final registry = container.get<MiddlewareRegistry>();
    registry.register(
      'demo.global.beta',
      (_) =>
          (ctx, next) async => await next(),
    );
    registry.register(
      'demo.group.beta',
      (_) =>
          (ctx, next) async => await next(),
    );
  }
}
