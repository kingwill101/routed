import 'dart:async';

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:routed/middlewares.dart' show localizationMiddleware;
import 'package:routed/src/config/specs/localization.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart'
    show Config, TranslationLoader, TranslatorContract;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed_view/routed_view.dart'; // file loader moved
import 'package:routed_view/routed_view.dart'; // locale manager moved
import 'package:routed_view/routed_view.dart'; // registry moved
import 'package:routed_view/routed_view.dart'; // resolvers moved
import 'package:routed_view/routed_view.dart'; // translator moved as routed;

/// Provides translation loader + translator bindings using the default
/// filesystem configured by the engine.
class LocalizationServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  file.FileSystem _fallbackFileSystem = const local.LocalFileSystem();
  static const LocalizationConfigSpec spec = LocalizationConfigSpec();
  static final LocaleResolverRegistry _resolverTemplate =
      _buildResolverTemplate();

  @override
  ConfigDefaults get defaultConfig {
    final values = spec.defaultsWithRoot();
    values['http'] = {
      'middleware_sources': {
        'routed.localization': {
          'global': ['routed.localization'],
        },
      },
    };

    return ConfigDefaults(
      docs: <ConfigDocEntry>[
        const ConfigDocEntry(
          path: 'http.middleware_sources',
          type: 'map',
          description:
              'Localization middleware references injected into the pipeline.',
          defaultValue: <String, Object?>{
            'routed.localization': <String, Object?>{
              'global': <String>['routed.localization'],
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
    if (container.has<EngineConfig>()) {
      _fallbackFileSystem = container.get<EngineConfig>().fileSystem;
    }

    final config = container.has<Config>() ? container.get<Config>() : null;
    final registry = _ensureResolverRegistry(container);
    final resolved = _resolveLocalizationConfig(config);
    final loader = _buildLoader(container, resolved);
    final translator = _buildTranslator(loader, resolved);
    final localeManager = _buildLocaleManager(resolved, config, registry);

    container
      ..instance<TranslationLoader>(loader)
      ..instance<TranslatorContract>(translator)
      ..instance<LocaleManager>(localeManager);

    _registerMiddleware(container);
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    final registry = _ensureResolverRegistry(container);
    final resolved = _resolveLocalizationConfig(config);
    final loader = _buildLoader(container, resolved);
    final translator = _buildTranslator(loader, resolved);
    final localeManager = _buildLocaleManager(resolved, config, registry);

    container
      ..instance<TranslationLoader>(loader)
      ..instance<TranslatorContract>(translator)
      ..instance<LocaleManager>(localeManager);
  }

  TranslationLoader _buildLoader(
    Container container,
    LocalizationConfig config,
  ) {
    final engineConfig = container.has<EngineConfig>()
        ? container.get<EngineConfig>()
        : null;
    final fs = engineConfig?.fileSystem ?? _fallbackFileSystem;
    final loader = FileTranslationLoader(fileSystem: fs);
    loader.setPaths(config.paths);
    loader.setJsonPaths(config.jsonPaths);
    loader.setNamespaces(config.namespaces);

    return loader;
  }

  TranslatorContract _buildTranslator(
    TranslationLoader loader,
    LocalizationConfig localeConfig,
  ) {
    return Translator(
      loader: loader,
      locale: localeConfig.defaultLocale,
      fallbackLocale: localeConfig.fallbackLocale,
    );
  }

  LocaleManager _buildLocaleManager(
    LocalizationConfig localeConfig,
    Config? config,
    LocaleResolverRegistry registry,
  ) {
    final resolvers = localeConfig.resolvers;
    final builtResolvers = _buildResolvers(
      registry,
      resolvers,
      localeConfig,
      localeConfig.resolverOptions,
      config,
    );

    return LocaleManager(
      defaultLocale: localeConfig.defaultLocale,
      fallbackLocale: localeConfig.fallbackLocale,
      resolvers: builtResolvers,
    );
  }

  List<LocaleResolver> _buildResolvers(
    LocaleResolverRegistry registry,
    List<String> order,
    LocalizationConfig shared,
    Map<String, Map<String, dynamic>> resolverOptions,
    Config? config,
  ) {
    final resolvers = <LocaleResolver>[];
    for (final raw in order) {
      final key = raw.trim();
      final factory = registry.resolve(key.toLowerCase());
      if (factory == null) {
        throw ProviderConfigException(
          'translation.resolvers entry "$raw" is not registered. '
          'Register custom resolvers via LocaleResolverRegistry or select one '
          'of the registered options (${_availableResolversForError(registry)}).',
        );
      }
      final ctx = LocaleResolverBuildContext(
        id: key,
        sharedOptions: LocaleResolverSharedOptions(
          queryParameter: shared.queryParameter,
          cookieName: shared.cookieName,
          sessionKey: shared.sessionKey,
          headerName: shared.headerName,
        ),
        options:
            resolverOptions[key.toLowerCase()] ?? const <String, dynamic>{},
        config: config,
      );
      resolvers.add(factory(ctx));
    }
    return resolvers;
  }

  void _registerMiddleware(Container container) {
    if (!container.has<MiddlewareRegistry>()) {
      return;
    }
    final registry = container.get<MiddlewareRegistry>();
    registry.register('routed.localization', (c) {
      final manager = c.get<LocaleManager>();
      return localizationMiddleware(manager);
    });
  }

  String _availableResolversForError(LocaleResolverRegistry registry) {
    final names = registry.identifiers.toList(growable: false);
    if (names.isEmpty) {
      return 'none registered';
    }
    return names.join(', ');
  }

  LocaleResolverRegistry _ensureResolverRegistry(Container container) {
    if (container.has<LocaleResolverRegistry>()) {
      final registry = container.get<LocaleResolverRegistry>();
      _seedRegistry(registry);
      return registry;
    }
    final registry = LocaleResolverRegistry.clone(_resolverTemplate);
    container.instance<LocaleResolverRegistry>(registry);
    return registry;
  }

  void _seedRegistry(LocaleResolverRegistry registry) {
    for (final name in _resolverTemplate.identifiers) {
      if (registry.contains(name)) {
        continue;
      }
      final factory = _resolverTemplate.resolve(name);
      if (factory != null) {
        registry.register(name, factory);
      }
    }
  }

  static LocaleResolverRegistry _buildResolverTemplate() {
    final registry = LocaleResolverRegistry();
    registry.register('query', (context) {
      return QueryLocaleResolver(
        parameter: context.sharedOptions.queryParameter,
      );
    });
    registry.register('cookie', (context) {
      return CookieLocaleResolver(cookieName: context.sharedOptions.cookieName);
    });
    registry.register('session', (context) {
      return SessionLocaleResolver(
        sessionKey: context.sharedOptions.sessionKey,
      );
    });
    registry.register('header', (context) {
      return HeaderLocaleResolver(headerName: context.sharedOptions.headerName);
    });
    return registry;
  }

  LocalizationConfig _resolveLocalizationConfig(Config? config) {
    if (config == null) {
      final defaults = spec.defaults();
      return spec.fromMap(defaults);
    }
    return spec.resolve(config);
  }
}
