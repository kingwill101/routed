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
  static bool _resolversRegistered = false;

  static const List<String> _defaultResolvers = <String>[
    'query',
    'cookie',
    'header',
  ];

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    docs: <ConfigDocEntry>[
      ConfigDocEntry(
        path: 'translation.paths',
        type: 'list<string>',
        description:
            'Directories scanned for `locale/group.(yaml|yml|json)` files.',
        defaultValue: ['resources/lang'],
      ),
      ConfigDocEntry(
        path: 'translation.json_paths',
        type: 'list<string>',
        description:
            'Directories containing flat `<locale>.json` dictionaries.',
        defaultValue: <String>[],
      ),
      ConfigDocEntry(
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
        defaultValue: _defaultResolvers,
      ),
      ConfigDocEntry(
        path: 'translation.query.parameter',
        type: 'string',
        description: 'Query parameter consulted for locale overrides.',
        defaultValue: 'locale',
      ),
      ConfigDocEntry(
        path: 'translation.cookie.name',
        type: 'string',
        description: 'Cookie name consulted for locale overrides.',
        defaultValue: 'locale',
      ),
      ConfigDocEntry(
        path: 'translation.session.key',
        type: 'string',
        description: 'Session key consulted for locale overrides.',
        defaultValue: 'locale',
      ),
      ConfigDocEntry(
        path: 'translation.header.name',
        type: 'string',
        description: 'Header inspected for Accept-Language fallbacks.',
        defaultValue: 'Accept-Language',
      ),
      ConfigDocEntry(
        path: 'translation.resolver_options',
        type: 'map',
        description:
            'Resolver-specific options keyed by resolver identifier.',
        defaultValue: <String, Object?>{},
      ),
      ConfigDocEntry(
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
    final loader = _buildLoader(container, config);
    final localeConfig = _resolveLocaleConfig(config);
    final translator = _buildTranslator(loader, localeConfig);
    final localeManager = _buildLocaleManager(localeConfig, config);

    container
      ..instance<TranslationLoader>(loader)
      ..instance<TranslatorContract>(translator)
      ..instance<LocaleManager>(localeManager);

    _registerMiddleware(container);
    _registerTemplateFilters();
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    final loader = _buildLoader(container, config);
    final localeConfig = _resolveLocaleConfig(config);
    final translator = _buildTranslator(loader, localeConfig);
    final localeManager = _buildLocaleManager(localeConfig, config);

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
    final translationNode = config?.get('translation');
    if (translationNode != null && translationNode is! Map) {
      throw ProviderConfigException('translation must be a map');
    }

    final paths = _readStringList(
      config?.get('translation.paths'),
      defaultValue: const ['resources/lang'],
      context: 'translation.paths',
    );
    loader.setPaths(paths);

    final jsonPaths = _readStringList(
      config?.get('translation.json_paths'),
      defaultValue: const <String>[],
      context: 'translation.json_paths',
    );
    loader.setJsonPaths(jsonPaths);

    final namespaces = _readStringMap(
      config?.get('translation.namespaces'),
      context: 'translation.namespaces',
    );
    loader.setNamespaces(namespaces);

    return loader;
  }

  _LocaleConfig _resolveLocaleConfig(Config? config) {
    final defaultLocale = _readLocale(config?.get('app.locale')) ?? 'en';
    final fallback =
        _readLocale(config?.get('app.fallback_locale')) ?? defaultLocale;
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
  ) {
    final resolvers = _readStringList(
      config?.get('translation.resolvers'),
      defaultValue: _defaultResolvers,
      context: 'translation.resolvers',
    );
    final queryParameter = _readString(
      config?.get('translation.query.parameter'),
      defaultValue: 'locale',
      context: 'translation.query.parameter',
    );
    final cookieName = _readString(
      config?.get('translation.cookie.name'),
      defaultValue: 'locale',
      context: 'translation.cookie.name',
    );
    final sessionKey = _readString(
      config?.get('translation.session.key'),
      defaultValue: 'locale',
      context: 'translation.session.key',
    );
    final headerName = _readString(
      config?.get('translation.header.name'),
      defaultValue: 'Accept-Language',
      context: 'translation.header.name',
    );

    final options = _ResolverOptions(
      queryParameter: queryParameter,
      cookieName: cookieName,
      sessionKey: sessionKey,
      headerName: headerName,
    );

    final resolverOptions =
        _readResolverOptions(config?.get('translation.resolver_options'));
    final builtResolvers =
        _buildResolvers(resolvers, options, resolverOptions, config);

    return LocaleManager(
      defaultLocale: localeConfig.defaultLocale,
      fallbackLocale: localeConfig.fallbackLocale,
      resolvers: builtResolvers,
    );
  }

  List<LocaleResolver> _buildResolvers(
    List<String> order,
    _ResolverOptions shared,
    Map<String, Map<String, dynamic>> resolverOptions,
    Config? config,
  ) {
    _registerDefaultResolvers();
    final registry = LocaleResolverRegistry.instance;
    final resolvers = <LocaleResolver>[];
    for (final raw in order) {
      final key = raw.trim();
      final factory = registry.resolve(key.toLowerCase());
      if (factory == null) {
        throw ProviderConfigException(
          'translation.resolvers entry "$raw" is not registered. '
          'Register custom resolvers via LocaleResolverRegistry or stick to '
          'built-ins (query, cookie, session, header).',
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
        options: resolverOptions[key.toLowerCase()] ?? const <String, dynamic>{},
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
    if (value is! Map) {
      throw ProviderConfigException('translation.resolver_options must be a map');
    }
    final result = <String, Map<String, dynamic>>{};
    value.forEach((key, entry) {
      if (key is! String) {
        throw ProviderConfigException(
          'translation.resolver_options keys must be strings',
        );
      }
      if (entry == null) {
        result[key.toLowerCase()] = <String, dynamic>{};
        return;
      }
      if (entry is! Map) {
        throw ProviderConfigException(
          'translation.resolver_options.$key must be a map',
        );
      }
      result[key.toLowerCase()] = entry.map(
        (k, v) => MapEntry(k.toString(), v),
      );
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

  List<String> _readStringList(
    Object? value, {
    required List<String> defaultValue,
    required String context,
  }) {
    if (value == null) {
      return defaultValue;
    }
    if (value is String) {
      return value.trim().isEmpty ? <String>[] : <String>[value.trim()];
    }
    if (value is Iterable) {
      final result = <String>[];
      for (final entry in value) {
        if (entry is! String) {
          throw ProviderConfigException('$context entries must be strings');
        }
        final trimmed = entry.trim();
        if (trimmed.isNotEmpty) {
          result.add(trimmed);
        }
      }
      return result;
    }
    throw ProviderConfigException('$context must be a string or list');
  }

  Map<String, String> _readStringMap(Object? value, {required String context}) {
    if (value == null) {
      return <String, String>{};
    }
    if (value is! Map) {
      throw ProviderConfigException('$context must be a map');
    }
    final result = <String, String>{};
    value.forEach((key, path) {
      if (key is! String || path is! String) {
        throw ProviderConfigException('$context entries must be strings');
      }
      final trimmedKey = key.trim();
      final trimmedPath = path.trim();
      if (trimmedKey.isEmpty || trimmedPath.isEmpty) {
        return;
      }
      result[trimmedKey] = trimmedPath;
    });
    return result;
  }

  String _readString(
    Object? value, {
    required String defaultValue,
    required String context,
  }) {
    if (value == null) {
      return defaultValue;
    }
    if (value is! String) {
      throw ProviderConfigException('$context must be a string');
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ProviderConfigException('$context must not be empty');
    }
    return trimmed;
  }

  String? _readLocale(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw ProviderConfigException('app locale keys must be strings');
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
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

  void _registerDefaultResolvers() {
    if (_resolversRegistered) {
      return;
    }
    final registry = LocaleResolverRegistry.instance;
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
      return HeaderLocaleResolver(
        headerName: context.sharedOptions.headerName,
      );
    });
    _resolversRegistered = true;
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
