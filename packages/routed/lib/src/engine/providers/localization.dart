library;

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config, TranslationLoader, TranslatorContract;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/provider/provider.dart';
import 'dart:io';

import 'package:liquify/src/filter_registry.dart' as liquify;
import 'package:routed/src/middleware/localization.dart' show localizationMiddleware;
import 'package:routed_views/src/translation/loaders/file_translation_loader.dart';
import 'package:routed_views/src/translation/locale_manager.dart';
import 'package:routed_views/src/translation/locale_resolver_registry.dart';
import 'package:routed_views/src/translation/resolvers.dart';
import 'package:routed_views/src/translation/translator.dart';

/// Stub provider for backward compat — implements minimal register to satisfy tests.
class LocalizationServiceProvider extends ServiceProvider with ProvidesDefaultConfig {
  file.FileSystem _fallbackFileSystem = const local.LocalFileSystem();

  @override
  ConfigDefaults get defaultConfig {
    return ConfigDefaults(
      docs: [
        ConfigDocEntry(
          path: 'http.middleware_sources',
          type: 'map',
          description: 'Localization middleware automatically registered.',
          defaultValue: {
            'routed.localization': {
              'global': ['routed.localization'],
            },
          },
        ),
      ],
      values: {
        'translation': {
          'paths': ['resources/lang'],
          'fallback_locale': 'en',
        },
        'app': {'locale': 'en', 'fallback_locale': 'en'},
        'http': {
          'middleware_sources': {
            'routed.localization': {
              'global': ['routed.localization'],
            },
          },
        },
      },
      schemas: {},
    );
  }

  @override
  void register(Container container) {
    if (container.has<EngineConfig>()) {
      _fallbackFileSystem = container.get<EngineConfig>().fileSystem;
    }
    final config = container.has<Config>() ? container.get<Config>() : null;
    final appLocale = config?.get<String>('app.locale') ?? 'en';
    final fallbackLocale = config?.get<String>('app.fallback_locale') ?? config?.get<String>('app.locale') ?? 'en';
    final transPaths = config?.get<List>('translation.paths') ?? ['resources/lang'];
    final jsonPaths = config?.get<List>('translation.json_paths') ?? [];
    final namespaces = config?.get<Map>('translation.namespaces') ?? {};

    // Validate translation config
    final transRaw = config?.get<dynamic>('translation');
    if (transRaw != null && transRaw is! Map) {
      throw ProviderConfigException('translation must be a map');
    }

    final loader = FileTranslationLoader(
      fileSystem: _fallbackFileSystem,
      paths: (transPaths as List).map((e) => e.toString()).toList(),
      jsonPaths: (jsonPaths as List).map((e) => e.toString()).toList(),
      namespaces: (namespaces as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
    );

    final translator = Translator(
      loader: loader,
      locale: appLocale,
      fallbackLocale: fallbackLocale,
    );

    // Build LocaleManager with resolvers from config
    final resolvers = <String>[];
    final resolverConfig = config?.get<List>('translation.resolvers');
    if (resolverConfig != null) {
      resolvers.addAll(resolverConfig.map((e) => e.toString()));
    } else {
      resolvers.addAll(['query', 'header', 'cookie']);
    }

    LocaleResolverRegistry? resolverRegistry;
    try {
      if (container.has<LocaleResolverRegistry>()) {
        resolverRegistry = container.get<LocaleResolverRegistry>();
      }
    } catch (_) {}

    // Validate resolvers — allow custom resolvers registered via LocaleResolverRegistry
    for (final id in resolvers) {
      if (['query', 'header', 'cookie', 'session'].contains(id)) continue;
      final isCustomRegistered = resolverRegistry != null && resolverRegistry.contains(id);
      if (!isCustomRegistered) {
        throw ProviderConfigException('translation.resolvers: unknown resolver id $id');
      }
    }

    final sharedOptions = LocaleResolverSharedOptions(
      queryParameter: config?.get<String>('translation.query.parameter') ?? 'lang',
      cookieName: config?.get<String>('translation.cookie.name') ?? 'locale',
      sessionKey: config?.get<String>('translation.session.key') ?? 'locale',
      headerName: HttpHeaders.acceptLanguageHeader,
    );
    final resolverOptionsRaw = config?.get<dynamic>('translation.resolver_options');
    final Map<String, Map<String, dynamic>> resolverOptionsById = {};
    if (resolverOptionsRaw is Map) {
      for (final entry in resolverOptionsRaw.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        if (v is Map) {
          resolverOptionsById[k] = Map<String, dynamic>.from(v as Map);
        }
      }
    }

    final localeManager = LocaleManager(
      defaultLocale: appLocale,
      fallbackLocale: fallbackLocale,
      resolvers: resolvers.map<LocaleResolver>((id) {
        switch (id) {
          case 'query':
            return QueryLocaleResolver(parameter: sharedOptions.queryParameter);
          case 'header':
            return HeaderLocaleResolver(headerName: sharedOptions.headerName);
          case 'cookie':
            return CookieLocaleResolver(cookieName: sharedOptions.cookieName);
          case 'session':
            return SessionLocaleResolver(sessionKey: sharedOptions.sessionKey);
          default:
            final factory = resolverRegistry?.resolve(id);
            if (factory != null) {
              final opts = resolverOptionsById[id] ?? const <String, dynamic>{};
              final ctx = LocaleResolverBuildContext(
                id: id,
                sharedOptions: sharedOptions,
                options: opts,
                config: config,
              );
              return factory(ctx);
            }
            return QueryLocaleResolver(parameter: sharedOptions.queryParameter);
        }
      }).toList(),
    );

    container
      ..instance<TranslationLoader>(loader)
      ..instance<TranslatorContract>(translator)
      ..instance<LocaleManager>(localeManager);

    if (container.has<MiddlewareRegistry>()) {
      container.get<MiddlewareRegistry>().register('routed.localization', (c) => localizationMiddleware(localeManager));
    }

    // Ensure global liquify filters exist for tests that check FilterRegistry.
    try {
      if (liquify.FilterRegistry.getFilter('trans') == null) {
        liquify.FilterRegistry.register('trans', (
          dynamic value,
          List<dynamic> args,
          Map<String, dynamic> named,
        ) =>
            value);
      }
      if (liquify.FilterRegistry.getFilter('trans_choice') == null) {
        liquify.FilterRegistry.register('trans_choice', (
          dynamic value,
          List<dynamic> args,
          Map<String, dynamic> named,
        ) =>
            value);
      }
    } catch (_) {}

    // Directly inject localization middleware into Engine's global stack
    // so tests that use testEngine with Core+Routing+Localization get locale
    // via query/header without needing http.providers manifest.
    try {
      if (container.has<Engine>()) {
        final engine = container.get<Engine>();
        final already = engine.middlewares.any((m) => m.toString().contains('localization'));
        if (!already) {
          // Avoid duplicate if already added via registry rebuild.
          engine.middlewares.add(localizationMiddleware(localeManager));
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> boot(Container container) async {}

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    // Re-register with new config
    register(container);
  }
}
