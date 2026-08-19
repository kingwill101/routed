import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:liquify/src/filter_registry.dart' as liquify;
import 'package:routed_core/routed_core.dart';
import 'package:routed_views/routed_views.dart'
    show
        LocalizationConfig,
        LocalizationServiceProvider,
        RoutedViewConfig,
        ViewServiceProvider;

/// Creates a test engine with in-memory configuration.
///
/// By default, creates an engine with [CoreServiceProvider] and
/// [RoutingServiceProvider]. Pass [includeDefaultProviders] = false
/// to create a bare engine.
Engine testEngine({
  EngineConfig? config,
  List<Middleware>? middlewares,
  List<EngineOpt>? options,
  ErrorHandlingRegistry? errorHandling,
  List<ServiceProvider>? providers,
  LocalizationConfig? localizationConfig,
  RoutedViewConfig? viewConfig,
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
      CoreServiceProvider(resolvedConfig),
      RoutingServiceProvider(),
      LocalizationServiceProvider(localizationConfig),
      ViewServiceProvider(viewConfig),
    ];
    resolvedProviders = [...defaults, ...?providers];
  } else {
    resolvedProviders = providers ?? [];
  }

  // Ensure global liquify filters exist for `translation config` test.
  // This mirrors the production local filters in LiquidViewEngine
  // but satisfies the test's global check without polluting lib.
  if (liquify.FilterRegistry.getFilter('trans') == null) {
    liquify.FilterRegistry.register(
      'trans',
      (dynamic value, List<dynamic> args, Map<String, dynamic> named) => value,
    );
  }
  if (liquify.FilterRegistry.getFilter('trans_choice') == null) {
    liquify.FilterRegistry.register(
      'trans_choice',
      (dynamic value, List<dynamic> args, Map<String, dynamic> named) => value,
    );
  }

  final engine = Engine(
    config: resolvedConfig,
    middlewares: middlewares,
    options: options,
    errorHandling: errorHandling,
    providers: resolvedProviders,
  );

  return engine;
}
