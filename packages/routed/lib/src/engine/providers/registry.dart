import 'package:routed/src/provider/provider.dart';

import 'cache.dart';
import 'core.dart';
import 'cors.dart';
import 'logging.dart';
import 'routing.dart';
import 'security.dart';
import 'sessions.dart';
import 'static_assets.dart';
import 'storage.dart';
import 'uploads.dart';
import 'views.dart';
import 'compression.dart';
import 'rate_limit.dart';
import 'observability.dart';
import 'auth.dart';

typedef ServiceProviderFactory = ServiceProvider Function();

class ProviderRegistration {
  ProviderRegistration({
    required this.id,
    required this.factory,
    required this.description,
  });

  final String id;
  final ServiceProviderFactory factory;
  final String description;
}

class ProviderRegistry {
  ProviderRegistry._();

  static final ProviderRegistry instance = ProviderRegistry._();

  final Map<String, ProviderRegistration>
  _providers = <String, ProviderRegistration>{
    'routed.core': ProviderRegistration(
      id: 'routed.core',
      factory: () => CoreServiceProvider(),
      description: 'Core services: config loader, engine bindings.',
    ),
    'routed.routing': ProviderRegistration(
      id: 'routed.routing',
      factory: () => RoutingServiceProvider(),
      description: 'Routing events and event manager bindings.',
    ),
    'routed.cache': ProviderRegistration(
      id: 'routed.cache',
      factory: () => CacheServiceProvider(),
      description: 'Cache manager bootstrap and defaults.',
    ),
    'routed.sessions': ProviderRegistration(
      id: 'routed.sessions',
      factory: () => SessionServiceProvider(),
      description: 'Session middleware and configuration.',
    ),
    'routed.uploads': ProviderRegistration(
      id: 'routed.uploads',
      factory: () => UploadsServiceProvider(),
      description: 'Multipart upload configuration defaults.',
    ),
    'routed.cors': ProviderRegistration(
      id: 'routed.cors',
      factory: () => CorsServiceProvider(),
      description: 'CORS configuration and middleware defaults.',
    ),
    'routed.security': ProviderRegistration(
      id: 'routed.security',
      factory: () => SecurityServiceProvider(),
      description: 'Security middleware (CSRF, headers, limits).',
    ),
    'routed.logging': ProviderRegistration(
      id: 'routed.logging',
      factory: () => LoggingServiceProvider(),
      description: 'HTTP logging defaults and helpers.',
    ),
    'routed.auth': ProviderRegistration(
      id: 'routed.auth',
      factory: () => AuthServiceProvider(),
      description: 'Authentication helpers (JWT middleware, validators).',
    ),
    'routed.observability': ProviderRegistration(
      id: 'routed.observability',
      factory: () => ObservabilityServiceProvider(),
      description:
          'Tracing, metrics, health endpoints, and error observer hooks.',
    ),
    'routed.compression': ProviderRegistration(
      id: 'routed.compression',
      factory: () => CompressionServiceProvider(),
      description: 'Response compression defaults and middleware.',
    ),
    'routed.rate_limit': ProviderRegistration(
      id: 'routed.rate_limit',
      factory: () => RateLimitServiceProvider(),
      description:
          'Rate limiting with token buckets, sliding windows, quotas, and failover modes.',
    ),
    'routed.storage': ProviderRegistration(
      id: 'routed.storage',
      factory: () => StorageServiceProvider(),
      description: 'Storage disks (local file systems, etc.).',
    ),
    'routed.static': ProviderRegistration(
      id: 'routed.static',
      factory: () => StaticAssetsServiceProvider(),
      description: 'Static asset serving configuration defaults.',
    ),
    'routed.views': ProviderRegistration(
      id: 'routed.views',
      factory: () => ViewServiceProvider(),
      description: 'View template configuration and engines.',
    ),
  };

  Iterable<ProviderRegistration> get registrations =>
      _providers.values.toList(growable: false);

  ProviderRegistration? resolve(String id) => _providers[id];

  bool has(String id) => _providers.containsKey(id);

  void register(
    String id, {
    required ServiceProviderFactory factory,
    String description = '',
  }) {
    _providers[id] = ProviderRegistration(
      id: id,
      factory: factory,
      description: description,
    );
  }
}
