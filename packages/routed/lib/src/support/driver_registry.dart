library;

import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/support/named_registry.dart';

/// Signature for driver documentation builders.
typedef DriverDocBuilder<TContext> =
    List<ConfigDocEntry> Function(TContext context);

/// Immutable metadata captured when registering a driver.
class DriverRegistration<TBuilder, TDocContext, TValidator> {
  DriverRegistration({
    required this.builder,
    this.documentation,
    this.validator,
    List<String> requiresConfig = const [],
  }) : requiresConfig = List<String>.unmodifiable(requiresConfig);

  /// Function that produces the driver instance.
  final TBuilder builder;

  /// Optional callback that declares configuration documentation entries.
  final DriverDocBuilder<TDocContext>? documentation;

  /// Optional validator invoked before the driver is considered valid.
  final TValidator? validator;

  /// Configuration keys required by the driver builder.
  final List<String> requiresConfig;
}

/// Shared infrastructure for Routed driver registries.
///
/// Base class for string-keyed driver registries.
abstract class DriverRegistryBase<
  TBuilder,
  TDocContext,
  TValidator,
  TRegistration extends DriverRegistration<TBuilder, TDocContext, TValidator>
>
    extends NamedRegistry<TRegistration> {
  DriverRegistryBase();

  /// Creates a registration object for the given driver [builder].
  TRegistration createRegistration(
    TBuilder builder, {
    DriverDocBuilder<TDocContext>? documentation,
    TValidator? validator,
    List<String> requiresConfig = const [],
  });

  /// Registers [builder] under [name], optionally attaching docs and validators.
  bool registerDriver(
    String name,
    TBuilder builder, {
    DriverDocBuilder<TDocContext>? documentation,
    TValidator? validator,
    List<String> requiresConfig = const [],
    bool overrideExisting = true,
  }) {
    final registration = createRegistration(
      builder,
      documentation: documentation,
      validator: validator,
      requiresConfig: requiresConfig,
    );
    return registerEntry(
      name,
      registration,
      overrideExisting: overrideExisting,
    );
  }

  /// Registers [builder] only when no existing driver uses [name].
  bool registerDriverIfAbsent(
    String name,
    TBuilder builder, {
    DriverDocBuilder<TDocContext>? documentation,
    TValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    return registerDriver(
      name,
      builder,
      documentation: documentation,
      validator: validator,
      requiresConfig: requiresConfig,
      overrideExisting: false,
    );
  }

  /// Removes the driver registered under [name], if any.
  void unregisterDriver(String name) => unregisterEntry(name);

  /// Whether a driver named [name] exists in the registry.
  bool hasDriver(String name) => containsEntry(name);

  /// Resolves the registration for [name], or `null` when absent.
  TRegistration? registrationFor(String name) => getEntry(name);

  /// Lists every driver name plus optional [include] identifiers.
  Iterable<String> driverNames({Iterable<String> include = const []}) {
    final names = <String>{...include, ...entryNames};
    final list = names.toList()..sort();
    return list;
  }

  /// Collects documentation for every registered driver.
  List<ConfigDocEntry> documentation({required String pathBase}) {
    final docs = <ConfigDocEntry>[];
    entries.forEach((driver, registration) {
      final builder = registration.documentation;
      if (builder == null) {
        return;
      }
      docs.addAll(builder(buildDocContext(driver, pathBase: pathBase)));
    });
    return docs;
  }

  /// Collects documentation for a single [driver], if provided.
  List<ConfigDocEntry> documentationFor(
    String driver, {
    required String pathBase,
  }) {
    final registration = getEntry(driver);
    if (registration == null || registration.documentation == null) {
      return const <ConfigDocEntry>[];
    }
    return registration.documentation!(
      buildDocContext(driver, pathBase: pathBase),
    );
  }

  /// Builds a documentation context for [driver] rooted at [pathBase].
  TDocContext buildDocContext(String driver, {required String pathBase});
}
