import 'package:routed_core/routed_core.dart' show ProviderRegistry;

import 'providers/logging.dart';

void registerRoutedLoggingProviders() {
  ProviderRegistry.instance.register(
    'routed.logging',
    factory: LoggingServiceProvider.new,
    description: 'HTTP logging defaults and helpers.',
  );
}
