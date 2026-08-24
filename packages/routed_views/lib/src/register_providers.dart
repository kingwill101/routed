import 'package:routed_core/routed_core.dart' show ProviderRegistry;

import 'package:routed_views/src/providers/localization.dart';
import 'package:routed_views/src/providers/view_provider.dart';

/// Registers the view and localization provider factories in the shared
/// registry.
///
/// Registration adds the `routed.views` and `routed.localization` identifiers
/// to the process-wide [ProviderRegistry]. It records factories only; provider
/// instances are created later by the application. Repeated calls are safe
/// because existing identifiers are preserved by the registry.
///
/// Call this during application composition when the application resolves
/// providers from the registry instead of constructing
/// [ViewServiceProvider] and [LocalizationServiceProvider] directly.
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
