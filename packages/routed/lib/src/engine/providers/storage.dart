import 'dart:async';

import 'package:file/file.dart' as file;
import 'package:path/path.dart' as p;
import 'package:routed/src/config/specs/storage.dart';
import 'package:routed/src/config/specs/storage_drivers.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/storage_defaults.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/cloud_storage_driver.dart';
import 'package:routed/src/storage/local_storage_driver.dart';
import 'package:routed/src/storage/storage_drivers.dart';
import 'package:routed/src/storage/storage_manager.dart';
import 'package:storage_fs/storage_fs.dart' as storage_fs;

/// {@template storage_provider_resolution}
/// Applies storage configuration to disk registrations.
///
/// Disk roots are normalized against `app.root`, and `StorageDefaults` is
/// registered so helper functions can resolve framework paths consistently.
///
/// Example:
/// ```dart
/// final defaults = container.get<StorageDefaults>();
/// final cachePath = defaults.frameworkPath('cache');
/// ```
/// {@endtemplate}

/// {@macro storage_provider_resolution}
class StorageServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  StorageManager? _managedManager;
  static bool _defaultsRegistered = false;
  static const StorageConfigSpec spec = StorageConfigSpec();

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
          pathBase: 'storage.disks.$driver',
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
      ...spec.docs(),
      const ConfigDocEntry(
        path: 'storage.disks.*.driver',
        type: 'string',
        description: 'Storage backend for this disk.',
        optionsBuilder: StorageServiceProvider.availableDriverNames,
      ),
      ...StorageServiceProvider.driverDocumentation(),
    ],
    values: spec.defaultsWithRoot(),
    schemas: spec.schemaWithRoot(),
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
        storageRoot: defaultStorageRootPath(),
      );
      final defaultName = manager.defaultDisk;
      final facadeDisks = <String, Map<String, dynamic>>{};
      final localFileSystems = <String, file.FileSystem>{};
      if (registered != null) {
        facadeDisks[registered.key] = registered.value;
        final disk = manager.disk(registered.key);
        if (disk is LocalStorageDisk) {
          localFileSystems[registered.key] = disk.fileSystem;
        }
      } else if (manager.hasDisk(defaultName)) {
        facadeDisks[defaultName] = _configFromDisk(manager.disk(defaultName));
        final disk = manager.disk(defaultName);
        if (disk is LocalStorageDisk) {
          localFileSystems[defaultName] = disk.fileSystem;
        }
      }
      _initializeStorageFacade(
        defaultDisk: defaultName,
        cloudDisk: null,
        disks: facadeDisks,
        localFileSystems: localFileSystems,
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
    final localFileSystems = <String, file.FileSystem>{};
    final resolvedConfig = spec.resolve(config);
    final defaultFs = manager.defaultFileSystem;
    final storageRoot = _normalizeStorageRoot(
      resolveStorageRootValue(resolvedConfig.root),
      config,
      defaultFs,
    );

    final defaultDisk = resolvedConfig.defaultDisk;
    manager.setDefault(defaultDisk);

    final cloudDisk = resolvedConfig.cloudDisk;

    if (resolvedConfig.disks.isNotEmpty) {
      resolvedConfig.disks.forEach((name, diskConfigEntry) {
        final diskConfig = Map<String, dynamic>.from(diskConfigEntry.toMap());
        final driverName =
            (diskConfig['driver']?.toString().toLowerCase() ?? 'local');
        if (name == 'local') {
          final diskFs = diskConfig['file_system'] is file.FileSystem
              ? diskConfig['file_system'] as file.FileSystem
              : defaultFs;
          final storageRootForDisk =
              storageRoot.isNotEmpty && diskFs != defaultFs
                  ? _normalizeStorageRoot(
                      resolveStorageRootValue(resolvedConfig.root),
                      config,
                      diskFs,
                    )
                  : storageRoot;
          final specContext = StorageDriverSpecContext(
            diskName: name,
            pathBase: 'storage.disks.$name',
            config: config,
          );
          final localResolved = LocalStorageDriver.spec.fromMap(
            diskConfig,
            context: specContext,
          );
          final existingRoot = localResolved.root;
          final shouldApplyStorageRoot =
              existingRoot == null ||
              existingRoot.isEmpty ||
              existingRoot == defaultStorageRootPath();
          if (shouldApplyStorageRoot && storageRootForDisk.isNotEmpty) {
            diskConfig['root'] = storageRootForDisk;
          }
        }
        if (driverName == 'local') {
          final diskFs = diskConfig['file_system'] is file.FileSystem
              ? diskConfig['file_system'] as file.FileSystem
              : defaultFs;
          final normalizedRoot = _normalizeDiskRoot(
            diskConfig['root'],
            config,
            diskFs,
          );
          if (normalizedRoot != null) {
            diskConfig['root'] = normalizedRoot;
          }
        }
        final registeredConfig = _registerDisk(
          container,
          manager,
          name,
          diskConfig,
          storageRoot: storageRoot,
        );
        facadeDisks[name] = registeredConfig;
        final diskInstance = manager.disk(name);
        if (diskInstance is LocalStorageDisk) {
          localFileSystems[name] = diskInstance.fileSystem;
        }
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
      final disk = manager.disk(fallback.key);
      if (disk is LocalStorageDisk) {
        localFileSystems[fallback.key] = disk.fileSystem;
      }
    } else if (manager.hasDisk(defaultDisk) &&
        !facadeDisks.containsKey(defaultDisk)) {
      facadeDisks[defaultDisk] = _configFromDisk(manager.disk(defaultDisk));
      final disk = manager.disk(defaultDisk);
      if (disk is LocalStorageDisk) {
        localFileSystems[defaultDisk] = disk.fileSystem;
      }
    }

    _initializeStorageFacade(
      defaultDisk: defaultDisk,
      cloudDisk: cloudDisk,
      disks: facadeDisks,
      localFileSystems: localFileSystems,
    );
    _registerStorageDefaults(container, manager, config: config);
  }

  /// {@macro storage_provider_resolution}
  String _normalizeStorageRoot(
    String root,
    Config config,
    file.FileSystem fs,
  ) {
    final trimmed = root.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    return _resolveAgainstAppRoot(config, trimmed, fs.path);
  }

  String _resolveAgainstAppRoot(
    Config config,
    String path,
    p.Context pathContext,
  ) {
    final normalized = pathContext.normalize(path);
    if (pathContext.isAbsolute(normalized)) {
      return normalized;
    }
    final appRoot = config.has('app.root')
        ? config.get<Object?>('app.root')
        : null;
    if (appRoot is String && appRoot.trim().isNotEmpty) {
      return pathContext.normalize(pathContext.join(appRoot.trim(), normalized));
    }
    return normalized;
  }

  /// {@macro storage_provider_resolution}
  String? _normalizeDiskRoot(
    Object? root,
    Config config,
    file.FileSystem fs,
  ) {
    if (root is! String) {
      return null;
    }
    final trimmed = root.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed == defaultStorageRootPath()) {
      return null;
    }
    return _resolveAgainstAppRoot(config, trimmed, fs.path);
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
    configCopy['driver'] = driver;
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
        configuration: configCopy,
        storageRoot: storageRoot,
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

  /// {@macro storage_provider_resolution}
  void _registerStorageDefaults(
    Container container,
    StorageManager manager, {
    Config? config,
  }) {
    final effectiveConfig =
        config ?? (container.has<Config>() ? container.get<Config>() : null);
    final defaults = effectiveConfig != null
        ? StorageDefaults.fromConfig(effectiveConfig, manager)
        : StorageDefaults.fromManager(manager);
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
    Map<String, file.FileSystem>? localFileSystems,
  }) {
    if (disks.isEmpty) {
      disks[defaultDisk] = {
        'driver': 'local',
        'root': localStorageDriver.resolveRoot(null, defaultDisk),
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

    if (localFileSystems == null || localFileSystems.isEmpty) {
      return;
    }

    for (final entry in localFileSystems.entries) {
      final name = entry.key;
      final fs = entry.value;
      final config = disks[name];
      if (config == null) {
        continue;
      }
      final driver = (config['driver'] ?? 'local').toString().toLowerCase();
      if (driver != 'local') {
        continue;
      }
      final adapter = storage_fs.FilesystemAdapter(
        storage_fs.DiskConfig.fromMap(config),
        fileSystem: fs,
      ).diskName(name);
      storage_fs.Storage.set(name, adapter);
    }
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
