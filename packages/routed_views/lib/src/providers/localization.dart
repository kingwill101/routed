import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:routed_core/routed_core.dart'
    show
        Container,
        Engine,
        EngineConfig,
        MiddlewareRegistry,
        ProvidesTypedConfiguration,
        ServiceProvider,
        TranslationLoader,
        TranslatorContract;
import 'package:routed_views/src/config.dart';
import 'package:routed_views/src/middleware/localization.dart'
    show localizationMiddleware;
import 'package:routed_views/src/translation/loaders/file_translation_loader.dart';
import 'package:routed_views/src/translation/locale_manager.dart';
import 'package:routed_views/src/translation/translator.dart';

/// Registers file-backed translation services and request-locale middleware.
///
/// [register] captures the engine filesystem when [EngineConfig] is already
/// available. [boot] then creates a [FileTranslationLoader], [Translator], and
/// [LocaleManager] from the immutable [configuration], and exposes them in the
/// container. When the corresponding integrations are present, boot also
/// registers `routed.localization` with [MiddlewareRegistry] and prepends the
/// middleware to the engine's middleware list.
///
/// The provider uses a local filesystem when no [EngineConfig] is available;
/// it does not require an engine or middleware registry in order to provide
/// the translation services.
class LocalizationServiceProvider extends ServiceProvider
    with ProvidesTypedConfiguration<LocalizationConfig> {
  /// Creates the localization provider with [configuration], or safe defaults.
  ///
  /// A default [LocalizationConfig] reads grouped translations from
  /// `resources/lang`, resolves `lang`, `locale`, session `locale`, and
  /// `Accept-Language` in that order, and uses `en` as both primary and
  /// fallback locale.
  LocalizationServiceProvider([LocalizationConfig? configuration])
    : configuration = configuration ?? LocalizationConfig();

  /// The immutable configuration consumed during [boot].
  @override
  final LocalizationConfig configuration;

  file.FileSystem _fallbackFileSystem = const local.LocalFileSystem();

  /// Captures the engine filesystem when one has already been registered.
  @override
  void register(Container container) {
    if (container.has<EngineConfig>()) {
      _fallbackFileSystem = container.get<EngineConfig>().fileSystem;
    }
  }

  /// Creates translation services and installs optional localization hooks.
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
      container.get<MiddlewareRegistry>().register(
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
