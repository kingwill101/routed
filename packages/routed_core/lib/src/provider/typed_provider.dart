import 'package:routed_core/src/config/typed.dart';
import 'package:routed_core/src/provider/provider.dart';

/// Adds an immutable typed configuration object to a service provider.
mixin ProvidesTypedConfiguration<T extends Object> on ServiceProvider
    implements TypedConfigurationProvider {
  /// The configuration value.
  T get configuration;

  @override
  Type get configurationType => T;

  @override
  Object get configurationObject => configuration;

  @override
  void validateConfiguration(ConfigValidationContext context) {
    final value = configuration;
    if (value case final ValidatableConfiguration validatable) {
      validatable.validate(context);
    }
  }
}

/// Optional contract for configuration objects with local invariants.
abstract interface class ValidatableConfiguration {
  /// Creates a [ValidatableConfiguration].
  void validate(ConfigValidationContext context);
}
