import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed_observability/routed_observability.dart';

/// Test engine with core + routing + observability providers.
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

  final List<ServiceProvider> resolvedProviders;
  if (includeDefaultProviders) {
    resolvedProviders = [
      CoreServiceProvider(configItems: configItems ?? const {}),
      RoutingServiceProvider(),
      ObservabilityServiceProvider(),
      ...?providers,
    ];
  } else {
    resolvedProviders = providers ?? [];
  }

  return Engine(
    config: resolvedConfig,
    middlewares: middlewares,
    options: options,
    errorHandling: errorHandling,
    providers: resolvedProviders,
  );
}
