import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/local_storage_driver.dart';

import '../spec.dart';

String defaultStorageRootPath() =>
    localStorageDriver.resolveRoot(null, 'local');

String storageRootTemplateDefault() {
  final root = defaultStorageRootPath().replaceAll("'", r"\'");
  return "{{ env.STORAGE_ROOT | default: '$root' }}";
}

String resolveStorageRootValue(String? value) {
  if (value == null) {
    return defaultStorageRootPath();
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return defaultStorageRootPath();
  }
  return trimmed;
}

class StorageDiskConfig {
  StorageDiskConfig({
    required this.name,
    required this.driver,
    required this.options,
  });

  final String name;
  final String driver;
  final Map<String, dynamic> options;

  factory StorageDiskConfig.fromMap(
    String name,
    Map<String, dynamic> map, {
    required String context,
  }) {
    final rawDriver = parseStringLike(
      map['driver'],
      context: '$context.driver',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final normalized = rawDriver?.toLowerCase();
    final driver = normalized == null || normalized.isEmpty
        ? 'local'
        : normalized;
    final options = Map<String, dynamic>.from(map);
    options['driver'] = driver;
    return StorageDiskConfig(name: name, driver: driver, options: options);
  }

  Map<String, dynamic> toMap() {
    final map = Map<String, dynamic>.from(options);
    map['driver'] = driver;
    return map;
  }
}

class StorageProviderConfig {
  const StorageProviderConfig({
    required this.defaultDisk,
    required this.cloudDisk,
    required this.root,
    required this.disks,
  });

  final String defaultDisk;
  final String? cloudDisk;
  final String? root;
  final Map<String, StorageDiskConfig> disks;
}

class StorageConfigSpec extends ConfigSpec<StorageProviderConfig> {
  const StorageConfigSpec();

  @override
  String get root => 'storage';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Storage Configuration',
    description: 'Filesystem and cloud storage configuration.',
    properties: {
      'default': ConfigSchema.string(
        description: 'Name of the disk to use when none is specified.',
        defaultValue: 'local',
      ),
      'cloud': ConfigSchema.string(
        description:
            'Disk name used when a "cloud" disk is required by helpers.',
      ),
      'root':
          ConfigSchema.string(
            description: 'Base filesystem path used by the default local disk.',
            defaultValue: storageRootTemplateDefault(),
          ).withMetadata({
            configDocMetaInheritFromEnv: 'STORAGE_ROOT',
            'default_note': 'Falls back to storage/app when not overridden.',
          }),
      'disks':
          ConfigSchema.object(
            description: 'Configured storage disks.',
            additionalProperties: true,
          ).withDefault({
            'local': {'driver': 'local', 'root': storageRootTemplateDefault()},
          }),
    },
  );

  @override
  StorageProviderConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final defaultRaw = parseStringLike(
      map['default'],
      context: 'storage.default',
      allowEmpty: true,
      throwOnInvalid: true,
    );
    final defaultDisk = defaultRaw == null || defaultRaw.isEmpty
        ? 'local'
        : defaultRaw;

    String? cloudDisk;
    if (map.containsKey('cloud')) {
      final cloudRaw = parseStringLike(
        map['cloud'],
        context: 'storage.cloud',
        allowEmpty: true,
        throwOnInvalid: true,
      );
      cloudDisk = (cloudRaw == null || cloudRaw.isEmpty) ? null : cloudRaw;
    }

    final rootValue = parseStringLike(
      map['root'],
      context: 'storage.root',
      allowEmpty: true,
      throwOnInvalid: true,
    );

    final disksRaw = map['disks'];
    final disks = <String, StorageDiskConfig>{};
    if (disksRaw != null) {
      final disksMap = stringKeyedMap(disksRaw as Object, 'storage.disks');
      disksMap.forEach((key, value) {
        if (value == null) {
          return;
        }
        final diskMap = stringKeyedMap(value as Object, 'storage.disks.$key');
        disks[key] = StorageDiskConfig.fromMap(
          key,
          diskMap,
          context: 'storage.disks.$key',
        );
      });
    }

    return StorageProviderConfig(
      defaultDisk: defaultDisk,
      cloudDisk: cloudDisk,
      root: rootValue,
      disks: disks,
    );
  }

  @override
  Map<String, dynamic> toMap(StorageProviderConfig value) {
    return {
      'default': value.defaultDisk,
      'cloud': value.cloudDisk,
      'root': value.root,
      'disks': value.disks.map((key, disk) => MapEntry(key, disk.toMap())),
    };
  }
}
