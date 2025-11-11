import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/storage_defaults.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/cloud_storage_driver.dart';
import 'package:routed/src/storage/local_storage_driver.dart';
import 'package:routed/src/storage/storage_drivers.dart';
import 'package:routed/src/storage/storage_manager.dart';
import 'package:storage_fs/storage_fs.dart' as storage_fs;

String _defaultStorageRootPath() =>
    localStorageDriver.resolveRoot(const <String, dynamic>{}, 'local');

String _storageRootTemplateDefault() {
  final root = _defaultStorageRootPath().replaceAll("'", r"\'");
  return "{{ env.STORAGE_ROOT | default: '$root' }}";
}

bool _looksLikeTemplate(String value) {
  final trimmed = value.trim();
  return trimmed.contains('{{') && trimmed.contains('}}');
}

String _resolveStorageRootValue(String? value) {
  if (value == null || value.isEmpty) {
    return _defaultStorageRootPath();
  }
  if (_looksLikeTemplate(value)) {
    return _defaultStorageRootPath();
  }
  return value;
}

String _resolveLocalDiskRoot(String? storageRoot, {required String diskName}) {
  final baseline = StorageDefaults.fromLocalRoot(
    storageRoot ?? _defaultStorageRootPath(),
  );
  if (diskName == 'local') {
    return baseline.localDiskRoot;
  }
  return p.posix.normalize(p.posix.join(baseline.storageBase, diskName));
}

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
    final docs = <ConfigDocEntry>[];
    for (final driver in StorageDriverRegistry.instance.drivers) {
      docs.addAll(
        StorageDriverRegistry.instance.documentationFor(
          driver,
          pathTemplate: 'storage.disks.$driver',
        ),
      );
    }
    return docs;
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
      ConfigDocEntry(
        path: 'storage.root',
        type: 'string',
        description: 'Base filesystem path used by the default local disk.',
        defaultValue: _storageRootTemplateDefault(),
        metadata: const {
          configDocMetaInheritFromEnv: 'STORAGE_ROOT',
          'default_note': 'Falls back to storage/app when not overridden.',
        },
      ),
      ConfigDocEntry(
        path: 'storage.disks',
        type: 'map',
        description: 'Configured storage disks.',
        defaultValueBuilder: () {
          return {
            'local': <String, Object?>{
              'driver': 'local',
              'root': _storageRootTemplateDefault(),
            },
          };
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
      final existing = container.get<StorageManager>();
      _registerStorageDefaults(container, existing);
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
      final registered = _registerDefaultDisk(
        container,
        manager,
        storageRoot: _defaultStorageRootPath(),
      );
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
    _registerStorageDefaults(container, manager);
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
    Map<String, dynamic>? storageMap;
    if (storageNode != null) {
      if (storageNode is! Map && storageNode is! Config) {
        throw ProviderConfigException('storage must be a map');
      }
      storageMap = stringKeyedMap(storageNode as Object, 'storage');
    }

    final storageRootToken = parseStringLike(
      (storageMap != null ? storageMap['root'] : null) ??
          config.get('storage.root'),
      context: 'storage.root',
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );
    final storageRoot = _resolveStorageRootValue(storageRootToken);

    if (storageMap == null) {
      final registered = _registerDefaultDisk(
        container,
        manager,
        storageRoot: storageRoot,
      );
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
      _registerStorageDefaults(container, manager);
      return;
    }

    final resolvedStorageMap = storageMap;

    final defaultToken = parseStringLike(
      resolvedStorageMap['default'],
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
      resolvedStorageMap['cloud'],
      context: 'storage.cloud',
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );
    final cloudDisk = cloudToken == null || cloudToken.isEmpty
        ? null
        : cloudToken;

    final disksNode =
        resolvedStorageMap['disks'] ?? config.get('storage.disks');
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
          storageRoot: storageRoot,
        );
        facadeDisks[name] = registeredConfig;
      });
    }

    final fallback = _registerDefaultDisk(
      container,
      manager,
      name: defaultDisk,
      storageRoot: storageRoot,
    );
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
    _registerStorageDefaults(container, manager);
  }

  Map<String, dynamic> _registerDisk(
    Container container,
    StorageManager manager,
    String name,
    Map<String, dynamic> rawConfig, {
    String? storageRoot,
  }) {
    final configCopy = Map<String, dynamic>.from(rawConfig);
    final driver = configCopy['driver']?.toString().toLowerCase() ?? 'local';
    final registry = StorageDriverRegistry.instance;
    final builder = registry.builderFor(driver);

    if (driver == 'local') {
      final rootToken = parseStringLike(
        configCopy['root'],
        context: 'storage.disks.$name.root',
        allowEmpty: true,
        coerceNonString: true,
        throwOnInvalid: false,
      );
      if (rootToken == null ||
          rootToken.isEmpty ||
          _looksLikeTemplate(rootToken)) {
        configCopy['root'] = _resolveLocalDiskRoot(storageRoot, diskName: name);
      } else {
        configCopy['root'] = rootToken;
      }
    }

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
        configuration: configCopy,
      ),
    );
    manager.registerDisk(name, disk);

    final sanitized = Map<String, dynamic>.from(configCopy)
      ..['driver'] = driver;

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

  void _registerStorageDefaults(Container container, StorageManager manager) {
    final defaults = StorageDefaults.fromManager(manager);
    container.instance<StorageDefaults>(defaults);
  }

  MapEntry<String, Map<String, dynamic>>? _registerDefaultDisk(
    Container container,
    StorageManager manager, {
    String? name,
    String? storageRoot,
  }) {
    final diskName = name ?? manager.defaultDisk;
    if (!manager.hasDisk(diskName)) {
      final config = _registerDisk(
        container,
        manager,
        diskName,
        <String, dynamic>{'driver': 'local'},
        storageRoot: storageRoot,
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
