import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_observability/routed_observability.dart';

/// Test engine with core + routing + observability providers.
Engine testEngine({
  EngineConfig? config,
  List<Middleware>? middlewares,
  List<EngineOpt>? options,
  ErrorHandlingRegistry? errorHandling,
  List<ServiceProvider>? providers,
  ObservabilityConfig? observabilityConfig,
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
      CoreServiceProvider(resolvedConfig),
      RoutingServiceProvider(),
      ObservabilityServiceProvider(observabilityConfig),
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
