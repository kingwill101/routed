import 'package:contextual/contextual.dart' as contextual;
import 'package:routed_core/routed_core.dart' show LoggingConfig;
import 'package:routed_core/src/container/container.dart';
import 'package:routed_core/src/support/driver_registry.dart';

/// Builds a contextual log driver from a registered channel configuration.
typedef LogDriverBuilder =
    contextual.LogDriver Function(LogDriverBuilderContext context);

/// Validates a registered log driver configuration before it is used.
typedef LogDriverValidator = void Function(LogDriverBuilderContext context);

/// Provides configuration and services to a custom log driver builder.
class LogDriverBuilderContext {
  /// Creates a builder context for a custom log driver.
  LogDriverBuilderContext({
    required this.name,
    required this.configPath,
    required this.options,
    required this.config,
    required this.container,
    required this.resolveChannel,
  });

  /// The configured channel name.
  final String name;

  /// The configuration path for the channel.
  final String configPath;

  /// Driver-specific options from the channel configuration.
  final Map<String, Object?> options;

  /// The immutable typed logging configuration for this engine.
  final LoggingConfig config;

  /// The application container for resolving services.
  final Container container;

  /// Resolves another configured channel by name.
  final contextual.LogDriver Function(String channelName) resolveChannel;
}

/// Stores a custom log driver builder and its optional validator.
class LogDriverRegistration
    extends DriverRegistration<LogDriverBuilder, LogDriverValidator> {
  /// Creates a registration for [builder] and an optional [validator].
  LogDriverRegistration({required super.builder, super.validator});
}

/// Registers builders for custom logging channel drivers.
class LogDriverRegistry
    extends
        DriverRegistryBase<
          LogDriverBuilder,
          LogDriverValidator,
          LogDriverRegistration
        > {
  /// Creates the registration object used by this registry.
  @override
  LogDriverRegistration createRegistration(
    LogDriverBuilder builder, {
    LogDriverValidator? validator,
  }) {
    return LogDriverRegistration(builder: builder, validator: validator);
  }

  /// Registers [builder] under [name].
  ///
  /// Existing registrations are replaced when [override] is `true`.
  void register(String name, LogDriverBuilder builder, {bool override = true}) {
    registerDriver(name, builder, overrideExisting: override);
  }

  /// Registers [builder] under [name] only when no registration exists.
  void registerIfAbsent(String name, LogDriverBuilder builder) {
    registerDriverIfAbsent(name, builder);
  }

  /// Whether a builder is registered under [name].
  bool contains(String name) => hasDriver(name);

  /// Returns the builder registered under [name], if any.
  LogDriverBuilder? builderFor(String name) => registrationFor(name)?.builder;
}
