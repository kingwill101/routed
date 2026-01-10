import 'package:routed/providers.dart';
import 'package:routed/routed.dart';

extension ProviderMetadata on ServiceProvider {
  String describe() {
    if (this is CoreServiceProvider) {
      return 'Core services: config loader, engine bindings.';
    }
    if (this is RoutingServiceProvider) {
      return 'Routing events and event manager bindings.';
    }
    if (this is CacheServiceProvider) {
      return 'Cache manager bootstrap and defaults.';
    }
    if (this is SessionServiceProvider) {
      return 'Session middleware and configuration.';
    }
    if (this is UploadsServiceProvider) {
      return 'Multipart upload configuration defaults.';
    }
    if (this is CorsServiceProvider) {
      return 'CORS configuration and middleware defaults.';
    }
    if (this is SecurityServiceProvider) {
      return 'Security middleware (CSRF, headers, limits).';
    }
    if (this is LoggingServiceProvider) {
      return 'HTTP logging defaults and helpers.';
    }
    if (this is StorageServiceProvider) {
      return 'Storage disks (local file systems, etc.).';
    }
    if (this is StaticAssetsServiceProvider) {
      return 'Static asset serving configuration defaults.';
    }
    if (this is ViewServiceProvider) {
      return 'View template configuration and engines.';
    }
    return '';
  }
}
