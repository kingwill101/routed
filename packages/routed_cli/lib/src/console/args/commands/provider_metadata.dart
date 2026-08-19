import 'package:routed_core/routed_core.dart';
import 'package:routed_logging/routed_logging.dart' show LoggingServiceProvider;

extension ServiceProviderDescribe on ServiceProvider {
  String describe() {
    if (this is CoreServiceProvider) {
      return 'Core engine bindings and lifecycle services.';
    }
    if (this is RoutingServiceProvider) {
      return 'Routing events and event manager bindings.';
    }
    if (this is UploadsServiceProvider) {
      return 'Typed multipart upload limits and guardrails.';
    }
    if (this is LoggingServiceProvider) {
      return 'HTTP logging defaults and helpers.';
    }
    return '';
  }
}
