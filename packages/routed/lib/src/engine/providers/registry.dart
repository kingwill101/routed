import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/support/named_registry.dart';

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
import '../../auth/provider.dart';
import 'localization.dart';

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

class ProviderRegistry extends NamedRegistry<ProviderRegistration> {
  ProviderRegistry._() {
    _registerDefaults();
  }

  static final ProviderRegistry instance = ProviderRegistry._();

  void _registerDefaults() {
    register(
      'routed.core',
      factory: () => CoreServiceProvider(),
      description: 'Core services: config loader, engine bindings.',
    );
    register(
      'routed.routing',
      factory: () => RoutingServiceProvider(),
      description: 'Routing events and event manager bindings.',
    );
    register(
      'routed.cache',
      factory: () => CacheServiceProvider(),
      description: 'Cache manager bootstrap and defaults.',
    );
    register(
      'routed.sessions',
      factory: () => SessionServiceProvider(),
      description: 'Session middleware and configuration.',
    );
    register(
      'routed.uploads',
      factory: () => UploadsServiceProvider(),
      description: 'Multipart upload configuration defaults.',
    );
    register(
      'routed.cors',
      factory: () => CorsServiceProvider(),
      description: 'CORS configuration and middleware defaults.',
    );
    register(
      'routed.security',
      factory: () => SecurityServiceProvider(),
      description: 'Security middleware (CSRF, headers, limits).',
    );
    register(
      'routed.logging',
      factory: () => LoggingServiceProvider(),
      description: 'HTTP logging defaults and helpers.',
    );
    register(
      'routed.auth',
      factory: () => AuthServiceProvider(),
      description: 'Authentication helpers (JWT middleware, validators).',
    );
    register(
      'routed.observability',
      factory: () => ObservabilityServiceProvider(),
      description:
          'Tracing, metrics, health endpoints, and error observer hooks.',
    );
    register(
      'routed.compression',
      factory: () => CompressionServiceProvider(),
      description: 'Response compression defaults and middleware.',
    );
    register(
      'routed.rate_limit',
      factory: () => RateLimitServiceProvider(),
      description:
          'Rate limiting with token buckets, sliding windows, quotas, and failover modes.',
    );
    register(
      'routed.storage',
      factory: () => StorageServiceProvider(),
      description: 'Storage disks (local file systems, etc.).',
    );
    register(
      'routed.static',
      factory: () => StaticAssetsServiceProvider(),
      description: 'Static asset serving configuration defaults.',
    );
    register(
      'routed.views',
      factory: () => ViewServiceProvider(),
      description: 'View template configuration and engines.',
    );
    register(
      'routed.localization',
      factory: () => LocalizationServiceProvider(),
      description: 'Translation loader/translator bindings and defaults.',
    );
  }

  Iterable<ProviderRegistration> get registrations =>
      entries.values.toList(growable: false);

  ProviderRegistration? resolve(String id) => getEntry(id);

  bool has(String id) => containsEntry(id);

  void register(
    String id, {
    required ServiceProviderFactory factory,
    String description = '',
  }) {
    registerEntry(
      id,
      ProviderRegistration(id: id, factory: factory, description: description),
    );
  }
}
