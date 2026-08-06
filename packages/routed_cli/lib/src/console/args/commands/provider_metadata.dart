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
    if (this is UploadsServiceProvider) {
      return 'Multipart upload configuration defaults.';
    }
    if (this is LoggingServiceProvider) {
      return 'HTTP logging defaults and helpers.';
    }
    return '';
  }
}
