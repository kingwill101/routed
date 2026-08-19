library;

import 'package:routed_core/src/support/named_registry.dart';

/// Immutable metadata captured when registering a driver.
class DriverRegistration<TBuilder, TValidator> {
  DriverRegistration({required this.builder, this.validator});

  /// Function that produces the driver instance.
  final TBuilder builder;

  /// Optional validator invoked before the driver is considered valid.
  final TValidator? validator;
}

/// Shared infrastructure for Routed driver registries.
///
/// Base class for string-keyed driver registries.
abstract class DriverRegistryBase<
  TBuilder,
  TValidator,
  TRegistration extends DriverRegistration<TBuilder, TValidator>
>
    extends NamedRegistry<TRegistration> {
  DriverRegistryBase();

  /// Creates a registration object for the given driver [builder].
  TRegistration createRegistration(TBuilder builder, {TValidator? validator});

  /// Registers [builder] under [name], optionally attaching a validator.
  bool registerDriver(
    String name,
    TBuilder builder, {
    TValidator? validator,
    bool overrideExisting = true,
  }) {
    final registration = createRegistration(builder, validator: validator);
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
    TValidator? validator,
  }) {
    return registerDriver(
      name,
      builder,
      validator: validator,
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
}
