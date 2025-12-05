import 'dart:async';

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:liquify/liquify.dart' show FilterRegistry;
import 'package:routed/middlewares.dart' show localizationMiddleware;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart'
    show Config, TranslationLoader, TranslatorContract;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/support/helpers.dart' show trans, transChoice;
import 'package:routed/src/translation/loaders/file_translation_loader.dart';
import 'package:routed/src/translation/locale_manager.dart';
import 'package:routed/src/translation/locale_resolver_registry.dart';
import 'package:routed/src/translation/resolvers.dart';
import 'package:routed/src/translation/translator.dart' as routed;

/// Provides translation loader + translator bindings using the default
/// filesystem configured by the engine.
class LocalizationServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  file.FileSystem _fallbackFileSystem = const local.LocalFileSystem();
  static bool _filtersRegistered = false;
  static final LocaleResolverRegistry _resolverTemplate =
      _buildResolverTemplate();

  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    docs: <ConfigDocEntry>[
      const ConfigDocEntry(
        path: 'translation.paths',
        type: 'list<string>',
        description:
            'Directories scanned for `locale/group.(yaml|yml|json)` files.',
        defaultValue: ['resources/lang'],
      ),
      const ConfigDocEntry(
        path: 'translation.json_paths',
        type: 'list<string>',
        description:
            'Directories containing flat `<locale>.json` dictionaries.',
        defaultValue: <String>[],
      ),
      const ConfigDocEntry(
        path: 'translation.namespaces',
        type: 'map<string,string>',
        description:
            'Vendor namespace hints mapping namespace => absolute directory.',
        defaultValue: <String, String>{},
      ),
      ConfigDocEntry(
        path: 'translation.resolvers',
        type: 'list<string>',
        description:
            'Ordered locale resolvers (query, cookie, header, session).',
        defaultValueBuilder: () => List<String>.from(_resolverDefaults()),
      ),
      const ConfigDocEntry(
        path: 'translation.query.parameter',
        type: 'string',
        description: 'Query parameter consulted for locale overrides.',
        defaultValue: 'locale',
      ),
      const ConfigDocEntry(
        path: 'translation.cookie.name',
        type: 'string',
        description: 'Cookie name consulted for locale overrides.',
        defaultValue: 'locale',
      ),
      const ConfigDocEntry(
        path: 'translation.session.key',
        type: 'string',
        description: 'Session key consulted for locale overrides.',
        defaultValue: 'locale',
      ),
      const ConfigDocEntry(
        path: 'translation.header.name',
        type: 'string',
        description: 'Header inspected for Accept-Language fallbacks.',
        defaultValue: 'Accept-Language',
      ),
      const ConfigDocEntry(
        path: 'translation.resolver_options',
        type: 'map',
        description: 'Resolver-specific options keyed by resolver identifier.',
        defaultValue: <String, Object?>{},
      ),
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
    ],
  );

  @override
  void register(Container container) {
    if (container.has<EngineConfig>()) {
      _fallbackFileSystem = container.get<EngineConfig>().fileSystem;
    }

    final config = container.has<Config>() ? container.get<Config>() : null;
    final registry = _ensureResolverRegistry(container);
    final loader = _buildLoader(container, config);
    final localeConfig = _resolveLocaleConfig(config);
    final translator = _buildTranslator(loader, localeConfig);
    final localeManager = _buildLocaleManager(localeConfig, config, registry);

    container
      ..instance<TranslationLoader>(loader)
      ..instance<TranslatorContract>(translator)
      ..instance<LocaleManager>(localeManager);

    _registerMiddleware(container);
    _registerTemplateFilters();
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    final registry = _ensureResolverRegistry(container);
    final loader = _buildLoader(container, config);
    final localeConfig = _resolveLocaleConfig(config);
    final translator = _buildTranslator(loader, localeConfig);
    final localeManager = _buildLocaleManager(localeConfig, config, registry);

    container
      ..instance<TranslationLoader>(loader)
      ..instance<TranslatorContract>(translator)
      ..instance<LocaleManager>(localeManager);
    _registerTemplateFilters();
  }

  TranslationLoader _buildLoader(Container container, Config? config) {
    final engineConfig = container.has<EngineConfig>()
        ? container.get<EngineConfig>()
        : null;
    final fs = engineConfig?.fileSystem ?? _fallbackFileSystem;
    final loader = FileTranslationLoader(fileSystem: fs);
    final translationNode = config?.get<Object>('translation');
    if (translationNode != null && translationNode is! Map) {
      throw ProviderConfigException('translation must be a map');
    }

    final paths = config?.getStringListOrNull('translation.paths') ?? const ['resources/lang'];
    loader.setPaths(paths);

    final jsonPaths = config?.getStringListOrNull('translation.json_paths') ?? const <String>[];
    loader.setJsonPaths(jsonPaths);

    loader.setNamespaces(config?.getStringMap('translation.namespaces') ?? const <String, String>{});

    return loader;
  }

  _LocaleConfig _resolveLocaleConfig(Config? config) {
    final defaultLocale = config?.getString('app.locale', defaultValue: 'en') ?? 'en';
    final fallback = config?.getStringOrNull('app.fallback_locale') ?? defaultLocale;
    return _LocaleConfig(
      defaultLocale: defaultLocale,
      fallbackLocale: fallback,
    );
  }

  TranslatorContract _buildTranslator(
    TranslationLoader loader,
    _LocaleConfig localeConfig,
  ) {
    return routed.Translator(
      loader: loader,
      locale: localeConfig.defaultLocale,
      fallbackLocale: localeConfig.fallbackLocale,
    );
  }

  LocaleManager _buildLocaleManager(
    _LocaleConfig localeConfig,
    Config? config,
    LocaleResolverRegistry registry,
  ) {
    final resolvers = config?.getStringListOrNull('translation.resolvers') ?? _resolverDefaults();
    final queryParameter = config?.getStringOrNull('translation.query.parameter') ?? 'locale';
    final cookieName = config?.getStringOrNull('translation.cookie.name') ?? 'locale';
    final sessionKey = config?.getStringOrNull('translation.session.key') ?? 'locale';
    final headerName = config?.getStringOrNull('translation.header.name') ?? 'Accept-Language';

    final options = _ResolverOptions(
      queryParameter: queryParameter,
      cookieName: cookieName,
      sessionKey: sessionKey,
      headerName: headerName,
    );

    final resolverOptions = _readResolverOptions(
      config?.get('translation.resolver_options'),
    );
    final builtResolvers = _buildResolvers(
      registry,
      resolvers,
      options,
      resolverOptions,
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
    _ResolverOptions shared,
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

  Map<String, Map<String, dynamic>> _readResolverOptions(Object? value) {
    if (value == null) {
      return <String, Map<String, dynamic>>{};
    }
    final Object normalizedSource = value;
    final normalized = stringKeyedMap(
      normalizedSource,
      'translation.resolver_options',
    );
    final result = <String, Map<String, dynamic>>{};
    normalized.forEach((key, entry) {
      if (entry == null) {
        result[key.toLowerCase()] = <String, dynamic>{};
      } else {
        final Object entryObject = entry as Object;
        result[key.toLowerCase()] = stringKeyedMap(
          entryObject,
          'translation.resolver_options.$key',
        );
      }
    });
    return result;
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

  void _registerTemplateFilters() {
    if (_filtersRegistered) {
      return;
    }

    FilterRegistry.register('trans', _transFilter);
    FilterRegistry.register('trans_choice', _transChoiceFilter);
    FilterRegistry.register('transChoice', _transChoiceFilter);

    _filtersRegistered = true;
  }

  List<String> _resolverDefaults() {
    return _resolverTemplate.identifiers.toList(growable: false);
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
}

dynamic _transFilter(
  dynamic value,
  List<dynamic> positional,
  Map<String, dynamic> named,
) {
  final key =
      _coerceString(value) ??
      (positional.isNotEmpty ? _coerceString(positional.first) : null);
  if (key == null) return value;

  final replacements = Map<String, dynamic>.from(named);
  final locale = replacements.remove('locale') ?? replacements.remove('lang');

  final resolved = trans(
    key,
    replacements: replacements.isEmpty ? null : replacements,
    locale: locale?.toString(),
  );

  return (resolved ?? key).toString();
}

dynamic _transChoiceFilter(
  dynamic value,
  List<dynamic> positional,
  Map<String, dynamic> named,
) {
  final key =
      _coerceString(value) ??
      (positional.isNotEmpty ? _coerceString(positional.first) : null);
  if (key == null) return value;

  final replacements = Map<String, dynamic>.from(named);
  final locale = replacements.remove('locale') ?? replacements.remove('lang');
  final dynamic countSource =
      replacements.remove('count') ??
      (positional.length > 1
          ? positional[1]
          : (positional.isNotEmpty ? positional.last : null));
  final num? count = _asNum(countSource);
  if (count == null) {
    return trans(
          key,
          replacements: replacements.isEmpty ? null : replacements,
          locale: locale?.toString(),
        )?.toString() ??
        key;
  }

  final resolved = transChoice(
    key,
    count,
    replacements: replacements.isEmpty ? null : replacements,
    locale: locale?.toString(),
  );
  return resolved.toString();
}

String? _coerceString(dynamic input) {
  if (input == null) return null;
  if (input is String) return input;
  return input.toString();
}

num? _asNum(dynamic input) {
  if (input == null) return null;
  if (input is num) return input;
  if (input is String) {
    return num.tryParse(input);
  }
  return null;
}

class _LocaleConfig {
  _LocaleConfig({required this.defaultLocale, required this.fallbackLocale});

  final String defaultLocale;
  final String fallbackLocale;
}

class _ResolverOptions {
  _ResolverOptions({
    required this.queryParameter,
    required this.cookieName,
    required this.sessionKey,
    required this.headerName,
  });

  final String queryParameter;
  final String cookieName;
  final String sessionKey;
  final String headerName;
}
