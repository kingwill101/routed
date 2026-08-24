import 'package:routed_core/routed_core.dart' show ProviderRegistry;

import 'package:routed_views/src/providers/localization.dart';
import 'package:routed_views/src/providers/view_provider.dart';

/// Registers view and localization provider factories in the shared registry.
void registerRoutedViewsProviders() {
  ProviderRegistry.instance
    ..register(
      'routed.views',
      factory: ViewServiceProvider.new,
      description: 'View template configuration and engines.',
    )
    ..register(
      'routed.localization',
      factory: LocalizationServiceProvider.new,
      description: 'Request locale resolution and translation loaders.',
    );
}
