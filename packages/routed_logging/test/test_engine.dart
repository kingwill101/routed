import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed_core/routed_core.dart';
import 'package:routed_logging/routed_logging.dart';

Engine testEngine({
  EngineConfig? config,
  List<Middleware>? middlewares,
  List<EngineOpt>? options,
  LoggingConfig? loggingConfig,
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
      CoreServiceProvider(resolvedConfig),
      RoutingServiceProvider(),
      LoggingServiceProvider(loggingConfig),
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
