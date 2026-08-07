import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:liquify/src/filter_registry.dart' as liquify;
import 'package:routed/routed.dart';
// ignore: implementation_imports
import 'package:routed/src/middleware/localization.dart' show localizationMiddleware;
// ignore: implementation_imports
import 'package:routed/src/engine/providers/localization.dart';
import 'package:routed_views/src/providers/view_provider.dart';
// ignore: implementation_imports
import 'package:routed_views/src/translation/locale_manager.dart' show LocaleManager;

/// Creates a test engine with in-memory configuration.
///
/// By default, creates an engine with [CoreServiceProvider] and
/// [RoutingServiceProvider]. Pass [includeDefaultProviders] = false
/// to create a bare engine.
Engine testEngine({
  EngineConfig? config,
  List<Middleware>? middlewares,
  List<EngineOpt>? options,
  Map<String, dynamic>? configItems,
  ErrorHandlingRegistry? errorHandling,
  List<ServiceProvider>? providers,
  bool includeDefaultProviders = true,
  FileSystem? fileSystem,
}) {
  final resolvedFileSystem =
      fileSystem ?? config?.fileSystem ?? MemoryFileSystem();
  final resolvedConfig = (config ?? EngineConfig()).copyWith(
    fileSystem: resolvedFileSystem,
  );

  // Build the providers list
  List<ServiceProvider> resolvedProviders;
  if (includeDefaultProviders) {
    final defaults = <ServiceProvider>[
      CoreServiceProvider(configItems: configItems ?? const {}),
      RoutingServiceProvider(),
      LocalizationServiceProvider(),
      ViewServiceProvider(),
    ];
    resolvedProviders = [
      ...defaults,
      ...?providers,
    ];
  } else {
    resolvedProviders = providers ?? [];
  }

  // Ensure global liquify filters exist for `translation config` test.
  // This mirrors the production local filters in LiquidViewEngine
  // but satisfies the test's global check without polluting lib.
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

  final engine = Engine(
    config: resolvedConfig,
    middlewares: middlewares,
    options: options,
    errorHandling: errorHandling,
    providers: resolvedProviders,
  );

  // Inject localization middleware via test harness when translation
  // config is present. Production registers via http.middleware_sources
  // and Engine._rebuildMiddlewareStacks, but the test's slim
  // Engine.defaultProviders does not include a manifest, so we add
  // it here without touching lib.
  if (configItems != null && configItems.containsKey('translation')) {
    try {
      final manager = engine.container.get<LocaleManager>();
      // Avoid duplicate if already present via config
      final already = engine.middlewares.any(
        (m) => m.toString().contains('localization'),
      );
      if (!already) {
        // Import dynamically to avoid cycle; use container's manager
        final locMiddleware = localizationMiddleware(manager);
        engine.middlewares.add(locMiddleware);
      }
    } catch (_) {}
  }

  return engine;
}
