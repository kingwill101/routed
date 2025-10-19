import 'package:routed/src/container/container.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_manager.dart';

typedef StorageDiskBuilder = StorageDisk Function(StorageDriverContext context);
typedef StorageDriverDocBuilder =
    List<ConfigDocEntry> Function(StorageDriverDocContext context);

class StorageDriverContext {
  StorageDriverContext({
    required this.container,
    required this.manager,
    required this.diskName,
    required this.configuration,
  });

  final Container container;
  final StorageManager manager;
  final String diskName;
  final Map<String, dynamic> configuration;

  T? option<T>(String key) {
    final value = configuration[key];
    if (value is T) {
      return value;
    }
    return null;
  }
}

class StorageDriverDocContext {
  StorageDriverDocContext({required this.driver, required this.pathTemplate});

  final String driver;
  final String pathTemplate;

  /// Convenience helper to build a config path relative to [pathTemplate].
  String path(String segment) => '$pathTemplate.$segment';
}

class _StorageDriverRegistration {
  _StorageDriverRegistration({required this.builder, this.documentation});

  final StorageDiskBuilder builder;
  final StorageDriverDocBuilder? documentation;
}

class StorageDriverRegistry {
  StorageDriverRegistry._internal();

  static final StorageDriverRegistry instance =
      StorageDriverRegistry._internal();

  final Map<String, _StorageDriverRegistration> _registrations =
      <String, _StorageDriverRegistration>{};

  void register(
    String driver,
    StorageDiskBuilder builder, {
    StorageDriverDocBuilder? documentation,
    bool overrideExisting = true,
  }) {
    if (!overrideExisting && _registrations.containsKey(driver)) {
      return;
    }
    _registrations[driver] = _StorageDriverRegistration(
      builder: builder,
      documentation: documentation,
    );
  }

  void unregister(String driver) {
    _registrations.remove(driver);
  }

  bool contains(String driver) => _registrations.containsKey(driver);

  StorageDiskBuilder? builderFor(String driver) =>
      _registrations[driver]?.builder;

  List<String> get drivers => _registrations.keys.toList(growable: false);

  List<ConfigDocEntry> documentation({required String pathTemplate}) {
    final docs = <ConfigDocEntry>[];
    _registrations.forEach((driver, registration) {
      final builder = registration.documentation;
      if (builder == null) {
        return;
      }
      final entries = builder(
        StorageDriverDocContext(driver: driver, pathTemplate: pathTemplate),
      );
      if (entries.isNotEmpty) {
        docs.addAll(entries);
      }
    });
    return docs;
  }

  List<ConfigDocEntry> documentationFor(
    String driver, {
    required String pathTemplate,
  }) {
    final registration = _registrations[driver];
    if (registration?.documentation == null) {
      return const <ConfigDocEntry>[];
    }
    return registration!.documentation!(
      StorageDriverDocContext(driver: driver, pathTemplate: pathTemplate),
    );
  }
}
