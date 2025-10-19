import 'dart:async';

import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/cloud_storage_driver.dart';
import 'package:routed/src/storage/local_storage_driver.dart';
import 'package:routed/src/storage/storage_drivers.dart';
import 'package:routed/src/storage/storage_manager.dart';
import 'package:storage_fs/storage_fs.dart' as storage_fs;

/// Provides storage disk configuration (local file systems, etc.).
class StorageServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  StorageManager? _managedManager;
  static bool _defaultsRegistered = false;

  static void registerDriver(
    String driver,
    StorageDiskBuilder builder, {
    StorageDriverDocBuilder? documentation,
    bool overrideExisting = true,
  }) {
    StorageDriverRegistry.instance.register(
      driver,
      builder,
      documentation: documentation,
      overrideExisting: overrideExisting,
    );
  }

  static void unregisterDriver(String driver) {
    StorageDriverRegistry.instance.unregister(driver);
  }

  static List<String> availableDriverNames() {
    _ensureDefaultDriversRegistered();
    final names = StorageDriverRegistry.instance.drivers.toList()..sort();
    return names;
  }

  static List<ConfigDocEntry> driverDocumentation() {
    _ensureDefaultDriversRegistered();
    return StorageDriverRegistry.instance.documentation(
      pathTemplate: 'storage.disks.*',
    );
  }

  static void _ensureDefaultDriversRegistered() {
    if (_defaultsRegistered) {
      return;
    }
    registerDriver(
      'local',
      localStorageDriver.build,
      documentation: localStorageDriver.documentation,
      overrideExisting: false,
    );
    registerDriver(
      "s3",
      cloudStorageDriver.build,
      documentation: cloudStorageDriver.documentation,
      overrideExisting: false,
    );
    _defaultsRegistered = true;
  }

  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    docs: [
      const ConfigDocEntry(
        path: 'storage.default',
        type: 'string',
        description: 'Name of the disk to use when none is specified.',
        defaultValue: 'local',
      ),
      const ConfigDocEntry(
        path: 'storage.cloud',
        type: 'string',
        description:
            'Disk name used when a "cloud" disk is required by helpers.',
        defaultValue: null,
      ),
      const ConfigDocEntry(
        path: 'storage.disks',
        type: 'map',
        description: 'Configured storage disks.',
        defaultValue: {
          'local': <String, Object?>{'driver': 'local'},
        },
      ),
      const ConfigDocEntry(
        path: 'storage.disks.*.driver',
        type: 'string',
        description: 'Storage backend for this disk.',
        optionsBuilder: StorageServiceProvider.availableDriverNames,
      ),
      ...StorageServiceProvider.driverDocumentation(),
    ],
  );

  @override
  void register(Container container) {
    _ensureDefaultDriversRegistered();

    if (container.has<StorageManager>()) {
      _managedManager = null;
      return;
    }

    final defaultFs = container.has<EngineConfig>()
        ? container.get<EngineConfig>().fileSystem
        : null;

    final manager = StorageManager(defaultFileSystem: defaultFs);
    _managedManager = manager;

    if (container.has<Config>()) {
      _applyConfig(container, manager, container.get<Config>());
    } else {
      final registered = _registerDefaultDisk(container, manager);
      final defaultName = manager.defaultDisk;
      final facadeDisks = <String, Map<String, dynamic>>{};
      if (registered != null) {
        facadeDisks[registered.key] = registered.value;
      } else if (manager.hasDisk(defaultName)) {
        facadeDisks[defaultName] = _configFromDisk(manager.disk(defaultName));
      }
      _initializeStorageFacade(
        defaultDisk: defaultName,
        cloudDisk: null,
        disks: facadeDisks,
      );
    }

    container.instance<StorageManager>(manager);
  }

  @override
  Future<void> boot(Container container) async {
    _ensureDefaultDriversRegistered();

    if (_managedManager != null && container.has<Config>()) {
      _applyConfig(container, _managedManager!, container.get<Config>());
    }
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    _ensureDefaultDriversRegistered();

    if (_managedManager != null) {
      _applyConfig(container, _managedManager!, config);
    }
  }

  void _applyConfig(
    Container container,
    StorageManager manager,
    Config config,
  ) {
    manager.clear();

    final facadeDisks = <String, Map<String, dynamic>>{};
    final storageNode = config.get('storage');
    if (storageNode == null) {
      final registered = _registerDefaultDisk(container, manager);
      final defaultName = manager.defaultDisk;
      if (registered != null) {
        facadeDisks[registered.key] = registered.value;
      } else if (manager.hasDisk(defaultName)) {
        facadeDisks[defaultName] = _configFromDisk(manager.disk(defaultName));
      }
      _initializeStorageFacade(
        defaultDisk: defaultName,
        cloudDisk: null,
        disks: facadeDisks,
      );
      return;
    }
    if (storageNode is! Map && storageNode is! Config) {
      throw ProviderConfigException('storage must be a map');
    }
    final storageMap = stringKeyedMap(storageNode as Object, 'storage');

    final defaultToken = parseStringLike(
      storageMap['default'],
      context: 'storage.default',
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );
    final defaultDisk = defaultToken == null || defaultToken.isEmpty
        ? 'local'
        : defaultToken;
    manager.setDefault(defaultDisk);

    final cloudToken = parseStringLike(
      storageMap['cloud'],
      context: 'storage.cloud',
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );
    final cloudDisk = cloudToken == null || cloudToken.isEmpty
        ? null
        : cloudToken;

    final disksNode = storageMap['disks'] ?? config.get('storage.disks');
    if (disksNode != null) {
      if (disksNode is! Map && disksNode is! Config) {
        throw ProviderConfigException('storage.disks must be a map');
      }
      final disksMap = stringKeyedMap(disksNode as Object, 'storage.disks');
      disksMap.forEach((name, value) {
        if (value == null) {
          return;
        }
        if (value is! Map && value is! Config) {
          throw ProviderConfigException('storage.disks.$name must be a map');
        }
        final registeredConfig = _registerDisk(
          container,
          manager,
          name,
          stringKeyedMap(value as Object, 'storage.disks.$name'),
        );
        facadeDisks[name] = registeredConfig;
      });
    }

    final fallback = _registerDefaultDisk(container, manager, defaultDisk);
    if (fallback != null) {
      facadeDisks[fallback.key] = fallback.value;
    } else if (manager.hasDisk(defaultDisk) &&
        !facadeDisks.containsKey(defaultDisk)) {
      facadeDisks[defaultDisk] = _configFromDisk(manager.disk(defaultDisk));
    }

    _initializeStorageFacade(
      defaultDisk: defaultDisk,
      cloudDisk: cloudDisk,
      disks: facadeDisks,
    );
  }

  Map<String, dynamic> _registerDisk(
    Container container,
    StorageManager manager,
    String name,
    Map<String, dynamic> rawConfig,
  ) {
    final driver = rawConfig['driver']?.toString().toLowerCase() ?? 'local';
    final registry = StorageDriverRegistry.instance;
    final builder = registry.builderFor(driver);

    if (builder == null) {
      final known = registry.drivers..sort();
      final message = known.isEmpty
          ? 'No storage drivers are registered.'
          : 'Supported drivers: ${known.join(", ")}.';
      throw ProviderConfigException(
        'Unsupported storage driver "$driver". $message',
      );
    }

    final disk = builder(
      StorageDriverContext(
        container: container,
        manager: manager,
        diskName: name,
        configuration: rawConfig,
      ),
    );
    manager.registerDisk(name, disk);

    final sanitized = Map<String, dynamic>.from(rawConfig)..['driver'] = driver;

    if (disk is LocalStorageDisk) {
      sanitized['root'] = disk.root;
    } else if (disk is CloudStorageDisk) {
      final diskConfig = disk.adapter.config;
      sanitized['driver'] = diskConfig.driver;
      sanitized['options'] = Map<String, dynamic>.from(diskConfig.options)
        ..removeWhere((_, v) => v == null);
      if (diskConfig.prefix != null && diskConfig.prefix!.isNotEmpty) {
        sanitized['prefix'] = diskConfig.prefix;
      }
      if (diskConfig.url != null && diskConfig.url!.isNotEmpty) {
        sanitized['url'] = diskConfig.url;
      }
      if (diskConfig.visibility != null && diskConfig.visibility!.isNotEmpty) {
        sanitized['visibility'] = diskConfig.visibility;
      }
      sanitized['throw'] = diskConfig.throw_;
      sanitized['report'] = diskConfig.report;
      sanitized['directory_separator'] = diskConfig.directorySeparator;
    }

    return sanitized;
  }

  MapEntry<String, Map<String, dynamic>>? _registerDefaultDisk(
    Container container,
    StorageManager manager, [
    String? name,
  ]) {
    final diskName = name ?? manager.defaultDisk;
    if (!manager.hasDisk(diskName)) {
      final config = _registerDisk(
        container,
        manager,
        diskName,
        <String, dynamic>{'driver': 'local'},
      );
      return MapEntry(diskName, config);
    }
    return null;
  }

  void _initializeStorageFacade({
    required String defaultDisk,
    String? cloudDisk,
    required Map<String, Map<String, dynamic>> disks,
  }) {
    if (disks.isEmpty) {
      disks[defaultDisk] = {
        'driver': 'local',
        'root': localStorageDriver.resolveRoot(const {}, defaultDisk),
      };
    }

    final facadeConfig = <String, dynamic>{
      'default': defaultDisk,
      'disks': disks.map(
        (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
      ),
    };
    if (cloudDisk != null && cloudDisk.isNotEmpty) {
      facadeConfig['cloud'] = cloudDisk;
    }

    storage_fs.Storage.initialize(facadeConfig);
  }

  Map<String, dynamic> _configFromDisk(StorageDisk disk) {
    if (disk is LocalStorageDisk) {
      return {'driver': 'local', 'root': disk.root};
    }
    if (disk is CloudStorageDisk) {
      final config = disk.adapter.config.toMap();
      final options = config['options'];
      if (options is Map) {
        config['options'] = Map<String, dynamic>.from(options);
      }
      return config;
    }
    return {'driver': 'local'};
  }
}
