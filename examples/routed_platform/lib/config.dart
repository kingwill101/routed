import 'package:routed/routed.dart';

import 'platform/platform_config.dart';
import 'platform/platform_provider.dart';

/// Typed application wiring shared by the server and Routed CLI tooling.
final class AppConfig {
  AppConfig({required Iterable<ServiceProvider> providers})
    : providers = List<ServiceProvider>.unmodifiable(providers);

  final List<ServiceProvider> providers;
}

/// Returns fresh providers for every engine created by the application.
AppConfig config() => AppConfig(
  providers: [
    CoreServiceProvider(),
    RoutingServiceProvider(),
    PlatformServiceProvider(
      const PlatformConfig(
        apiToken: 'demo-token',
        defaultTenant: 'demo-tenant',
        defaultNamespace: 'default',
      ),
    ),
  ],
);
