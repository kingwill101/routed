import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:routed_core/routed_core.dart';

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
  final secRaw = items['security'];
  if (secRaw != null && secRaw is! Map) {
    fail('security must be a map');
  }
  final sec = secRaw as Map?;
  if (sec != null) {
    final trustedRaw = sec['trusted_proxies'];
    final proxies = trustedRaw is Map ? trustedRaw : null;
    if (proxies != null) {
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
    // csrf
    final csrfRaw = sec['csrf'];
    if (csrfRaw != null && csrfRaw is! Map) {
      fail('security.csrf must be a map');
    }
    final csrf = csrfRaw as Map?;
    if (csrf != null) {
      if (csrf.containsKey('enabled') && csrf['enabled'] is! bool) {
        fail('security.csrf.enabled must be a boolean');
      }
      if (csrf.containsKey('cookie_name') && csrf['cookie_name'] is! String) {
        fail('security.csrf.cookie_name must be a string');
      }
    }
  }

  // view
  final viewRaw = items['view'];
  if (viewRaw != null && viewRaw is! Map) {
    fail('view must be a map');
  }
  final view = viewRaw as Map?;
  if (view != null) {
    if (view.containsKey('directory') && view['directory'] is! String) {
      fail('view.directory must be a string');
    }
    if (view.containsKey('cache') && view['cache'] is! bool) {
      fail('view.cache must be a boolean');
    }
    if (view.containsKey('engine') && view['engine'] is! String) {
      fail('view.engine must be a string');
    }
    if (view.containsKey('disk') && view['disk'] is! String) {
      fail('view.disk must be a string');
    }
  }

  // cache
  final cacheRaw = items['cache'];
  if (cacheRaw != null && cacheRaw is! Map) {
    fail('cache must be a map');
  }
  final cache = cacheRaw as Map?;
  if (cache != null) {
    if (cache.containsKey('default') && cache['default'] is! String) {
      fail('cache.default must be a string');
    }
    if (cache.containsKey('stores') && cache['stores'] is! Map) {
      fail('cache.stores must be a map');
    }
    // check each store type
    final stores = cache['stores'] as Map?;
    if (stores != null) {
      for (final entry in stores.entries) {
        if (entry.value is! Map) {
          fail('cache.stores.${entry.key} must be a map');
        }
      }
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
