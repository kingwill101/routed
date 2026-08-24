import 'package:routed_core/src/config/typed.dart';
import 'package:routed_core/src/engine/config.dart' show EtagStrategy;
import 'package:routed_core/src/provider/typed_provider.dart';

/// Configures the engine's route matching and response negotiation behavior.
class RoutingConfig implements ValidatableConfiguration {
  /// Creates routing configuration with the default engine behavior.
  const RoutingConfig({
    this.redirectTrailingSlash = true,
    this.handleMethodNotAllowed = true,
    this.defaultOptionsEnabled = true,
    this.etagStrategy = EtagStrategy.disabled,
  });

  /// Whether a path with the opposite trailing-slash form is redirected.
  final bool redirectTrailingSlash;

  /// Whether unmatched methods produce a method-not-allowed response.
  final bool handleMethodNotAllowed;

  /// Whether the router automatically handles `OPTIONS` requests.
  final bool defaultOptionsEnabled;

  /// The strategy used to generate and validate entity tags.
  final EtagStrategy etagStrategy;

  /// Validates the routing configuration.
  @override
  void validate(ConfigValidationContext context) {}
}
