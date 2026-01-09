import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed/routed.dart';

Engine testEngine({
  EngineConfig? config,
  List<Middleware>? middlewares,
  List<EngineOpt>? options,
  Map<String, dynamic>? configItems,
  ErrorHandlingRegistry? errorHandling,
  ConfigLoaderOptions? configOptions,
  List<ServiceProvider>? providers,
  bool includeDefaultProviders = true,
  FileSystem? fileSystem,
}) {
  final resolvedFileSystem =
      fileSystem ??
      config?.fileSystem ??
      configOptions?.fileSystem ??
      MemoryFileSystem();
  final resolvedConfig = (config ?? EngineConfig()).copyWith(
    fileSystem: resolvedFileSystem,
  );
  final resolvedOptions = (configOptions ?? const ConfigLoaderOptions())
      .copyWith(fileSystem: resolvedFileSystem);

  return Engine(
    config: resolvedConfig,
    middlewares: middlewares,
    options: options,
    configItems: configItems,
    errorHandling: errorHandling,
    configOptions: resolvedOptions,
    providers: providers,
    includeDefaultProviders: includeDefaultProviders,
  );
}
