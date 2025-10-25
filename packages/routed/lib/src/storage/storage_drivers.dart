import 'package:routed/src/container/container.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_manager.dart';
import 'package:routed/src/support/named_registry.dart';
export 'local_storage_driver.dart' show LocalStorageDisk;

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

class StorageDriverRegistration {
  StorageDriverRegistration({
    required this.builder,
    required this.origin,
    this.documentation,
  });

  final StorageDiskBuilder builder;
  final StackTrace origin;
  final StorageDriverDocBuilder? documentation;
}

class StorageDriverRegistry extends NamedRegistry<StorageDriverRegistration> {
  StorageDriverRegistry._internal();

  static final StorageDriverRegistry instance =
      StorageDriverRegistry._internal();

  void register(
    String driver,
    StorageDiskBuilder builder, {
    StorageDriverDocBuilder? documentation,
    bool overrideExisting = true,
  }) {
    final registration = StorageDriverRegistration(
      builder: builder,
      origin: StackTrace.current,
      documentation: documentation,
    );
    final stored = registerEntry(
      driver,
      registration,
      overrideExisting: overrideExisting,
    );
    if (!stored) {
      return;
    }
  }

  void unregister(String driver) => unregisterEntry(driver);

  bool contains(String driver) => containsEntry(driver);

  StorageDiskBuilder? builderFor(String driver) => getEntry(driver)?.builder;

  List<String> get drivers => entryNames.toList(growable: false);

  List<ConfigDocEntry> documentation({required String pathTemplate}) {
    final docs = <ConfigDocEntry>[];
    entries.forEach((driver, registration) {
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
    final registration = getEntry(driver);
    if (registration?.documentation == null) {
      return const <ConfigDocEntry>[];
    }
    return registration!.documentation!(
      StorageDriverDocContext(driver: driver, pathTemplate: pathTemplate),
    );
  }

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
      'Storage driver "$name" is already registered.\n'
      'Original registration stack trace:\n${existing.origin}',
    );
  }
}
