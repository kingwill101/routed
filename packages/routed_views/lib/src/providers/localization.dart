library;

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:routed_core/routed_core.dart'
    show
        Container,
        Engine,
        EngineConfig,
        MiddlewareRegistry,
        ServiceProvider,
        TranslatorContract,
        TranslationLoader,
        ProvidesTypedConfiguration;

import 'package:routed_views/src/middleware/localization.dart'
    show localizationMiddleware;
import 'package:routed_views/src/translation/loaders/file_translation_loader.dart';
import 'package:routed_views/src/translation/locale_manager.dart';
import 'package:routed_views/src/translation/translator.dart';
import '../config.dart';

/// Registers the localization services and middleware configuration.
class LocalizationServiceProvider extends ServiceProvider
    with ProvidesTypedConfiguration<LocalizationConfig> {
  /// Creates the localization provider with [configuration], or defaults.
  LocalizationServiceProvider([LocalizationConfig? configuration])
    : configuration = configuration ?? LocalizationConfig();

  @override
  final LocalizationConfig configuration;

  file.FileSystem _fallbackFileSystem = const local.LocalFileSystem();

  @override
  void register(Container container) {
    if (container.has<EngineConfig>()) {
      _fallbackFileSystem = container.get<EngineConfig>().fileSystem;
    }
  }

  @override
  Future<void> boot(Container container) async {
    final config = configuration;
    final loader = FileTranslationLoader(
      fileSystem: _fallbackFileSystem,
      paths: config.paths,
      jsonPaths: config.jsonPaths,
      namespaces: config.namespaces,
    );

    final translator = Translator(
      loader: loader,
      locale: config.defaultLocale,
      fallbackLocale: config.fallbackLocale,
    );

    final resolvers = config.resolvers;

    final localeManager = LocaleManager(
      defaultLocale: config.defaultLocale,
      fallbackLocale: config.fallbackLocale,
      resolvers: resolvers,
    );

    container
      ..instance<TranslationLoader>(loader)
      ..instance<TranslatorContract>(translator)
      ..instance<LocaleManager>(localeManager);

    if (container.has<MiddlewareRegistry>()) {
      final registry = container.get<MiddlewareRegistry>();
      registry.register(
        'routed.localization',
        (c) => localizationMiddleware(localeManager),
      );
    }
    if (container.has<Engine>()) {
      final engine = container.get<Engine>();
      engine.middlewares.insert(0, localizationMiddleware(localeManager));
    }
  }
}
