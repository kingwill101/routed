import 'package:routed_core/providers.dart' show ProviderRegistry;

import 'providers/localization.dart';
import 'providers/view_provider.dart';

/// Registers view + localization providers for `http.providers` resolution.
void registerRoutedViewsProviders() {
  final registry = ProviderRegistry.instance;
  registry.register(
    'routed.views',
    factory: ViewServiceProvider.new,
    description: 'View template configuration and engines.',
  );
  registry.register(
    'routed.localization',
    factory: LocalizationServiceProvider.new,
    description: 'Request locale resolution and translation loaders.',
  );
}
