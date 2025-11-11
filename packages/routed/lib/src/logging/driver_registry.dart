import 'package:contextual/contextual.dart' as contextual;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/support/driver_registry.dart';

typedef LogDriverBuilder =
    contextual.LogDriver Function(LogDriverBuilderContext context);
typedef LogDriverValidator = void Function(LogDriverBuilderContext context);
typedef LogDriverDocBuilder = DriverDocBuilder<LogDriverDocContext>;

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
  final Config config;
  final Container container;
  final contextual.LogDriver Function(String channelName) resolveChannel;
}

class LogDriverDocContext {
  LogDriverDocContext({required this.driver, required this.pathBase});

  final String driver;
  final String pathBase;

  String path(String segment) => '$pathBase.$segment';
}

class LogDriverRegistration
    extends
        DriverRegistration<
          LogDriverBuilder,
          LogDriverDocContext,
          LogDriverValidator
        > {
  LogDriverRegistration({
    required super.builder,
    super.documentation,
    super.validator,
    super.requiresConfig,
  });
}

class LogDriverRegistry
    extends
        DriverRegistryBase<
          LogDriverBuilder,
          LogDriverDocContext,
          LogDriverValidator,
          LogDriverRegistration
        > {
  @override
  LogDriverRegistration createRegistration(
    LogDriverBuilder builder, {
    DriverDocBuilder<LogDriverDocContext>? documentation,
    LogDriverValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    return LogDriverRegistration(
      builder: builder,
      documentation: documentation,
      validator: validator,
      requiresConfig: requiresConfig,
    );
  }

  @override
  LogDriverDocContext buildDocContext(
    String driver, {
    required String pathBase,
  }) {
    return LogDriverDocContext(driver: driver, pathBase: pathBase);
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
