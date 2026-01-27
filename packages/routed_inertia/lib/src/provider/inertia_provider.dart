import 'package:inertia_dart/inertia_dart.dart';
import 'package:routed/routed.dart';
import 'package:routed/providers.dart';

import '../config/inertia_config.dart';
import '../middleware/routed_inertia_middleware.dart';

/// Service provider that configures Inertia defaults and middleware.
class InertiaServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  InertiaServiceProvider({
    String Function()? versionResolver,
    SsrGateway? ssrGateway,
  }) : _versionResolver = versionResolver,
       _ssrGatewayOverride = ssrGateway;

  static const InertiaConfigSpec spec = InertiaConfigSpec();

  final String Function()? _versionResolver;
  final SsrGateway? _ssrGatewayOverride;
  InertiaConfig? _resolvedConfig;

  @override
  ConfigDefaults get defaultConfig {
    final values = spec.defaultsWithRoot();
    values['http'] = {
      'middleware_sources': {
        'routed.inertia': {
          'global': ['routed.inertia.middleware'],
        },
      },
    };

    return ConfigDefaults(
      docs: [
        const ConfigDocEntry(
          path: 'http.middleware_sources',
          type: 'map',
          description: 'Inertia middleware references registered globally.',
          defaultValue: <String, Object?>{
            'routed.inertia': <String, Object?>{
              'global': <String>['routed.inertia.middleware'],
            },
          },
        ),
        ...spec.docs(),
      ],
      values: values,
      schemas: spec.schemaWithRoot(),
    );
  }

  @override
  void register(Container container) {
    final registry = container.get<MiddlewareRegistry>();
    registry.register('routed.inertia.middleware', (_) => _middleware);

    if (container.has<Config>()) {
      _applyConfig(container, container.get<Config>());
    } else {
      _applyDefaults(container);
    }
  }

  @override
  Future<void> boot(Container container) async {
    if (container.has<Config>()) {
      _applyConfig(container, container.get<Config>());
    }
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    _applyConfig(container, config);
  }

  Middleware get _middleware {
    return RoutedInertiaMiddleware(versionResolver: _resolveVersion).call;
  }

  void _applyDefaults(Container container) {
    final defaults = spec.defaults();
    final resolved = spec.fromMap(defaults);
    _storeConfig(container, resolved);
  }

  void _applyConfig(Container container, Config config) {
    final resolved = spec.resolve(config);
    _storeConfig(container, resolved);
  }

  void _storeConfig(Container container, InertiaConfig resolved) {
    final gateway = _ssrGatewayOverride ?? _buildGateway(resolved);
    final configured = resolved.copyWith(
      versionResolver: _versionResolver,
      ssrGateway: gateway,
    );
    _resolvedConfig = configured;
    container.instance<InertiaConfig>(configured);
    container.instance<InertiaSsrSettings>(configured.ssr);
  }

  String _resolveVersion() {
    final override = _versionResolver?.call();
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return _resolvedConfig?.version ?? '';
  }

  SsrGateway? _buildGateway(InertiaConfig config) {
    if (!config.ssr.enabled) {
      return null;
    }
    final endpoint = config.ssr.resolveRenderEndpoint();
    if (endpoint == null) {
      return null;
    }
    if (config.ssr.ensureBundleExists) {
      final bundle = config.ssr.bundleDetector().detect();
      if (bundle == null) {
        return null;
      }
    }
    return HttpSsrGateway(
      endpoint,
      healthEndpoint: config.ssr.resolveHealthEndpoint(),
    );
  }
}

/// Register the Inertia provider with the routed registry.
void registerRoutedInertiaProvider(
  ProviderRegistry registry, {
  bool overrideExisting = false,
}) {
  if (!overrideExisting && registry.has('routed.inertia')) {
    return;
  }
  registry.register(
    'routed.inertia',
    factory: () => InertiaServiceProvider(),
    description: 'Inertia defaults, middleware, and SSR integration.',
  );
}
