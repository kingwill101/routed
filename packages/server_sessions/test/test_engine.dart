import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed/routed.dart';
import 'package:routed_sessions/routed_sessions.dart';
import 'package:server_sessions/server_sessions.dart';

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
    resolvedProviders = [
      CoreServiceProvider(configItems: configItems ?? const {}),
      RoutingServiceProvider(),
      ...?providers,
    ];
  } else {
    resolvedProviders = providers ?? [];
  }

  final engine = Engine(
    config: resolvedConfig,
    middlewares: middlewares,
    options: options,
    errorHandling: errorHandling,
    providers: resolvedProviders,
  );

  // If SessionConfig is present via withSessionConfig, ensure sessionMiddleware
  // is added. Production would do this via SessionServiceProvider +
  // http.middleware_sources, but the slim testEngine uses only core+routing,
  // so we add it here without touching lib.
  try {
    if (engine.container.has<SessionConfig>()) {
      final hasMiddleware = engine.middlewares.any(
        (m) => m.toString().contains('session'),
      );
      if (!hasMiddleware) {
        final cfg = engine.container.get<SessionConfig>();
        final store = cfg.store as SessionStore;
        engine.middlewares.add(sessionMiddleware(store));
        // Rebuild middleware stacks if needed
        try {
          // ignore: avoid_dynamic_calls
          (engine as dynamic)._rebuildMiddlewareStacks();
        } catch (_) {}
      }
    }
  } catch (_) {}

  return engine;
}
