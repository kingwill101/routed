import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:liquify/src/filter_registry.dart' as liquify;
import 'package:routed/routed.dart';
import 'package:routed/src/engine/providers/localization.dart';
import 'package:routed_views/src/providers/view_provider.dart';

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

  return Engine(
    config: resolvedConfig,
    middlewares: middlewares,
    options: options,
    errorHandling: errorHandling,
    providers: resolvedProviders,
  );
}
