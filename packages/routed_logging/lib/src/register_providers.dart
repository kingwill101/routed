import 'package:routed_core/routed_core.dart' show ProviderRegistry;

import 'package:routed_logging/src/providers/logging.dart';

/// Registers Routed's built-in logging provider in the global provider
/// registry.
void registerRoutedLoggingProviders() {
  ProviderRegistry.instance.register(
    'routed.logging',
    factory: LoggingServiceProvider.new,
    description: 'HTTP logging defaults and helpers.',
  );
}
