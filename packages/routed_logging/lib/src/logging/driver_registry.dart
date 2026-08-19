import 'package:contextual/contextual.dart' as contextual;
import 'package:routed_core/src/container/container.dart';
import 'package:routed_core/routed_core.dart' show LoggingConfig;
import 'package:routed_core/src/support/driver_registry.dart';

typedef LogDriverBuilder =
    contextual.LogDriver Function(LogDriverBuilderContext context);
typedef LogDriverValidator = void Function(LogDriverBuilderContext context);

class LogDriverBuilderContext {
  LogDriverBuilderContext({
    required this.name,
    required this.configPath,
    required this.options,
    required this.config,
    required this.container,
    required this.resolveChannel,
  });

  final String name;
  final String configPath;
  final Map<String, Object?> options;

  /// The immutable typed logging configuration for this engine.
  final LoggingConfig config;
  final Container container;
  final contextual.LogDriver Function(String channelName) resolveChannel;
}

class LogDriverRegistration
    extends DriverRegistration<LogDriverBuilder, LogDriverValidator> {
  LogDriverRegistration({required super.builder, super.validator});
}

class LogDriverRegistry
    extends
        DriverRegistryBase<
          LogDriverBuilder,
          LogDriverValidator,
          LogDriverRegistration
        > {
  @override
  LogDriverRegistration createRegistration(
    LogDriverBuilder builder, {
    LogDriverValidator? validator,
  }) {
    return LogDriverRegistration(builder: builder, validator: validator);
  }

  void register(String name, LogDriverBuilder builder, {bool override = true}) {
    registerDriver(name, builder, overrideExisting: override);
  }

  void registerIfAbsent(String name, LogDriverBuilder builder) {
    registerDriverIfAbsent(name, builder);
  }

  bool contains(String name) => hasDriver(name);

  LogDriverBuilder? builderFor(String name) => registrationFor(name)?.builder;
}
