/// Template rendering and request localization integrations for Routed.
///
/// This library is the public entry point for `ViewServiceProvider`,
/// `LocalizationServiceProvider`, typed view and localization configuration,
/// locale resolvers, translation loaders, and `EngineContext` rendering
/// extensions. Applications normally compose the providers directly:
///
/// ```dart
/// import 'package:routed_core/routed_core.dart';
/// import 'package:routed_views/routed_views.dart';
///
/// final engine = await Engine.create(
///   providers: [
///     ...Engine.defaultProviders,
///     ViewServiceProvider(RoutedViewConfig(directory: 'views')),
///     LocalizationServiceProvider(),
///   ],
/// );
/// ```
///
/// Use `registerRoutedViewsProviders` instead when an application composes
/// providers through `ProviderRegistry`. The exported extensions keep view
/// rendering and localization host-neutral across Routed's supported servers.
library;

export 'src/config.dart' show LocalizationConfig, RoutedViewConfig;
export 'src/engine_ext.dart';
export 'src/middleware/localization.dart' show localizationMiddleware;
export 'src/providers/localization.dart' show LocalizationServiceProvider;
export 'src/providers/view_provider.dart' show ViewServiceProvider;
export 'src/register_providers.dart' show registerRoutedViewsProviders;
export 'src/render_ext.dart';
export 'src/translation/constants.dart' show kRequestLocaleAttribute;
export 'src/translation/loaders/file_translation_loader.dart'
    show FileTranslationLoader;
export 'src/translation/locale_manager.dart' show LocaleManager;
export 'src/translation/locale_resolution.dart'
    show LocaleLookup, LocaleResolutionContext;
export 'src/translation/message_selector.dart' show MessageSelector;
export 'src/translation/resolvers.dart'
    show
        CookieLocaleResolver,
        HeaderLocaleResolver,
        LocaleResolver,
        QueryLocaleResolver,
        SessionLocaleResolver,
        sanitizeLocale;
export 'src/translation/translator.dart' show Translator;
export 'src/translation_ext.dart';
export 'src/view/engine_manager.dart' show ViewEngineManager;
export 'src/view/engines/liquid_engine.dart' show LiquidRoot, LiquidViewEngine;
export 'src/view/view.dart';
export 'src/view/view_engine.dart'
    show TemplateNotFoundException, ViewEngine, kViewEngineContextKey;
export 'src/view/view_extensions.dart'
    show ViewExtensionRegistration, ViewExtensionRegistry;
export 'src/view_ext.dart';
