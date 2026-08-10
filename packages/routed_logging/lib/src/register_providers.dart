import 'package:routed_core/providers.dart' show ProviderRegistry;

import 'providers/logging.dart';

void registerRoutedLoggingProviders() {
  ProviderRegistry.instance.register(
    'routed.logging',
    factory: LoggingServiceProvider.new,
    description: 'HTTP logging defaults and helpers.',
  );
}
