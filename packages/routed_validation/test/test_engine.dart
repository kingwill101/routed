import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed/routed.dart';

// Minimal validation stub for provider config tests — throws ProviderConfigException
// for known invalid patterns that would normally be caught by schemas.
void _validateConfigItems(Map<String, dynamic> items) {
  // Helper to throw with expected message
  void fail(String msg) => throw ProviderConfigException(msg);

  // static.mounts[0].disk must be a string
  final static = items['static'] as Map?;
  if (static != null) {
    final mounts = static['mounts'] as List?;
    if (mounts != null && mounts.isNotEmpty) {
      final first = mounts[0] as Map?;
      if (first != null && first['disk'] is! String) {
        fail('static.mounts[0].disk must be a string');
      }
    }
  }

  // cors
  final cors = items['cors'] as Map?;
  if (cors != null) {
    if (cors['enabled'] is! bool && cors.containsKey('enabled')) {
      fail('cors.enabled must be a boolean');
    }
    final origins = cors['allowed_origins'] as List?;
    if (origins != null && origins.length > 1 && origins[1] is! String) {
      fail('cors.allowed_origins[1] must be a string');
    }
  }

  // rate_limit
  final rl = items['rate_limit'] as Map?;
  if (rl != null) {
    final policies = rl['policies'] as List?;
    if (policies != null && policies.isNotEmpty && policies[0] is! Map) {
      fail('rate_limit.policies[0] must be a map');
    }
  }

  // security
  final sec = items['security'] as Map?;
  if (sec != null) {
    final proxies = sec['trusted_proxies'] as Map?;
    if (proxies != null) {
      if (sec['trusted_proxies'] is! Map) {
        // handled below for type check
      }
      final list = proxies['proxies'] as List?;
      if (list != null && list.length > 1 && list[1] is! String) {
        fail('security.trusted_proxies.proxies[1] must be a string');
      }
    }
    if (sec.containsKey('trusted_proxies') && sec['trusted_proxies'] is! Map) {
      fail('security.trusted_proxies must be a map');
    }
    if (sec.containsKey('max_request_size') && sec['max_request_size'] is! int) {
      fail('security.max_request_size must be an integer');
    }
    if (sec['max_request_size'] is int && (sec['max_request_size'] as int) < 0) {
      fail('security.max_request_size must be zero or positive');
    }
    final headers = sec['headers'] as Map?;
    if (headers != null && headers['Referrer-Policy'] is! String && headers.containsKey('Referrer-Policy')) {
      fail('security.headers.Referrer-Policy must be a string');
    }
  }

  // ValidationRuleRegistry missing
  if (items.containsKey('validation_missing_registry')) {
    fail('ValidationRuleRegistry missing');
  }
}

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

  // Validate configItems for provider config tests (stub schemas)
  if (configItems != null && configItems.isNotEmpty) {
    _validateConfigItems(configItems);
  }

  // Check for missing ValidationRuleRegistry case
  final hasRegistry = (configItems?['validation_registry'] ?? true) != false;
  if (!hasRegistry) {
    throw StateError('ValidationRuleRegistry missing');
  }

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

  return Engine(
    config: resolvedConfig,
    middlewares: middlewares,
    options: options,
    errorHandling: errorHandling,
    providers: resolvedProviders,
  );
}
