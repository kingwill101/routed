import 'package:routed/src/container/container.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_manager.dart';
import 'package:routed/src/support/driver_registry.dart';

export 'local_storage_driver.dart' show LocalStorageDisk;

/// A function that builds a [StorageDisk] using the provided [StorageDriverContext].
typedef StorageDiskBuilder = StorageDisk Function(StorageDriverContext context);

/// A function that generates a list of [ConfigDocEntry] for documentation purposes
/// using the provided [StorageDriverDocContext].
typedef StorageDriverDocBuilder =
    List<ConfigDocEntry> Function(StorageDriverDocContext context);

/// Context for a storage driver, providing necessary dependencies and configuration.
class StorageDriverContext {
  /// Creates a new [StorageDriverContext].
  ///
  /// [container] is the dependency injection container.
  /// [manager] is the storage manager instance.
  /// [diskName] is the name of the storage disk.
  /// [configuration] is the configuration map for the driver.
  /// [storageRoot] is an optional root path for storage.
  StorageDriverContext({
    required this.container,
    required this.manager,
    required this.diskName,
    required this.configuration,
    this.storageRoot,
  });

  /// The dependency injection container.
  final Container container;

  /// The storage manager instance.
  final StorageManager manager;

  /// The name of the storage disk.
  final String diskName;

  /// The configuration map for the driver.
  final Map<String, dynamic> configuration;

  /// The optional root path for storage.
  final String? storageRoot;

  /// Retrieves the value of type [T] associated with the given [key] in the configuration.
  ///
  /// Returns `null` if the value is not of type [T] or does not exist.
  T? option<T>(String key) {
    final value = configuration[key];
    if (value is T) {
      return value;
    }
    return null;
  }
}

/// Context for generating documentation for a storage driver.
class StorageDriverDocContext {
  /// Creates a new [StorageDriverDocContext].
  ///
  /// [driver] is the name of the storage driver.
  /// [pathBase] is the base path for configuration paths.
  StorageDriverDocContext({required this.driver, required this.pathBase});

  /// The name of the storage driver.
  final String driver;

  /// The base path for configuration paths.
  final String pathBase;

  /// Builds a configuration path relative to [pathBase].
  ///
  /// [segment] is the segment to append to the base path.
  String path(String segment) => '$pathBase.$segment';
}

/// A registration entry for a storage driver.
class StorageDriverRegistration
    extends
        DriverRegistration<
          StorageDiskBuilder,
          StorageDriverDocContext,
          StorageDriverValidator
        > {
  /// Creates a new [StorageDriverRegistration].
  ///
  /// [builder] is the function to build the storage disk.
  /// [documentation] is an optional function to generate documentation.
  /// [validator] is an optional function to validate the driver context.
  /// [requiresConfig] is a list of required configuration keys.
  StorageDriverRegistration({
    required super.builder,
    super.documentation,
    super.validator,
    super.requiresConfig,
  });
}

/// A function that validates a [StorageDriverContext].
typedef StorageDriverValidator = void Function(StorageDriverContext context);

/// A registry for managing storage driver registrations.
class StorageDriverRegistry
    extends
        DriverRegistryBase<
          StorageDiskBuilder,
          StorageDriverDocContext,
          StorageDriverValidator,
          StorageDriverRegistration
        > {
  StorageDriverRegistry._internal();

  /// The singleton instance of [StorageDriverRegistry].
  static final StorageDriverRegistry instance =
      StorageDriverRegistry._internal();

  @override
  StorageDriverRegistration createRegistration(
    StorageDiskBuilder builder, {
    DriverDocBuilder<StorageDriverDocContext>? documentation,
    StorageDriverValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    return StorageDriverRegistration(
      builder: builder,
      documentation: documentation,
      validator: validator,
      requiresConfig: requiresConfig,
    );
  }

  @override
  StorageDriverDocContext buildDocContext(
    String driver, {
    required String pathBase,
  }) {
    return StorageDriverDocContext(driver: driver, pathBase: pathBase);
  }

  /// Registers a new storage driver.
  ///
  /// [driver] is the name of the driver.
  /// [builder] is the function to build the storage disk.
  /// [documentation] is an optional function to generate documentation.
  /// [overrideExisting] determines whether to override an existing driver with the same name.
  /// [validator] is an optional function to validate the driver context.
  /// [requiresConfig] is a list of required configuration keys.
  void register(
    String driver,
    StorageDiskBuilder builder, {
    StorageDriverDocBuilder? documentation,
    bool overrideExisting = true,
    StorageDriverValidator? validator,
    List<String> requiresConfig = const [],
  }) {
    registerDriver(
      driver,
      builder,
      documentation: documentation,
      validator: validator,
      requiresConfig: requiresConfig,
      overrideExisting: overrideExisting,
    );
  }

  /// Unregisters a storage driver by its name.
  ///
  /// [driver] is the name of the driver to unregister.
  void unregister(String driver) => unregisterEntry(driver);

  /// Checks if a storage driver with the given name is registered.
  ///
  /// [driver] is the name of the driver to check.
  bool contains(String driver) => containsEntry(driver);

  /// Retrieves the builder function for the storage driver with the given name.
  ///
  /// [driver] is the name of the driver.
  StorageDiskBuilder? builderFor(String driver) => getEntry(driver)?.builder;

  /// Returns a list of all registered driver names.
  List<String> get drivers => entryNames.toList(growable: false);

  @override
  bool onDuplicate(
    String name,
    StorageDriverRegistration existing,
    bool overrideExisting,
  ) {
    if (!overrideExisting) {
      return false;
    }
    throw ProviderConfigException(
      'Storage driver "$name" is already registered.'
      '${duplicateDiagnostics(name)}',
    );
  }
}
