import 'package:file/file.dart' as file;
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/config/schema.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

import '../spec.dart';

class StaticMountConfig {
  const StaticMountConfig({
    required this.route,
    required this.disk,
    required this.path,
    required this.index,
    required this.listDirectories,
    required this.fileSystem,
    required this.root,
  });

  factory StaticMountConfig.fromMap(
    Map<String, dynamic> map, {
    required String contextPath,
  }) {
    String? routeValue;
    if (map.containsKey('route')) {
      routeValue = parseStringLike(
        map['route'],
        context: '$contextPath.route',
        allowEmpty: true,
        throwOnInvalid: true,
      );
    }
    if (routeValue == null || routeValue.isEmpty) {
      routeValue = parseStringLike(
        map['prefix'],
        context: '$contextPath.prefix',
        allowEmpty: true,
        throwOnInvalid: true,
      );
    }
    routeValue = routeValue == null || routeValue.isEmpty ? '/' : routeValue;

    final diskRaw =
        parseStringLike(
          map['disk'],
          context: '$contextPath.disk',
          allowEmpty: true,
          throwOnInvalid: true,
        );
    final diskName = (diskRaw == null || diskRaw.isEmpty) ? null : diskRaw.trim();

    final pathValue =
        parseStringLike(
          map['path'],
          context: '$contextPath.path',
          allowEmpty: true,
          throwOnInvalid: true,
        ) ??
        '';

    final indexRaw =
        parseStringLike(
          map['index'],
          context: '$contextPath.index',
          allowEmpty: true,
          throwOnInvalid: true,
        );
    final indexValue = (indexRaw == null || indexRaw.isEmpty) ? null : indexRaw;

    final listDirectories =
        parseBoolLike(
          map['list_directories'],
          context: '$contextPath.list_directories',
          throwOnInvalid: true,
        ) ??
        false;
    final directoryListing =
        parseBoolLike(
          map['directory_listing'],
          context: '$contextPath.directory_listing',
          throwOnInvalid: true,
        ) ??
        false;

    final customFs = map['file_system'];
    file.FileSystem? fileSystem;
    if (customFs != null) {
      if (customFs is! file.FileSystem) {
        throw ProviderConfigException(
          '$contextPath.file_system must implement FileSystem',
        );
      }
      fileSystem = customFs;
    }

    final rootValue =
        parseStringLike(
          map['root'],
          context: '$contextPath.root',
          allowEmpty: true,
          throwOnInvalid: true,
        );

    return StaticMountConfig(
      route: routeValue,
      disk: diskName,
      path: pathValue,
      index: indexValue,
      listDirectories: listDirectories || directoryListing,
      fileSystem: fileSystem,
      root: rootValue,
    );
  }

  final String route;
  final String? disk;
  final String path;
  final String? index;
  final bool listDirectories;
  final file.FileSystem? fileSystem;
  final String? root;
}

class StaticAssetsConfig {
  const StaticAssetsConfig({required this.enabled, required this.mounts});

  final bool enabled;
  final List<StaticMountConfig> mounts;
}

class StaticAssetsConfigSpec extends ConfigSpec<StaticAssetsConfig> {
  const StaticAssetsConfigSpec();

  @override
  String get root => 'static';

  @override
  Schema? get schema =>
      ConfigSchema.object(
        title: 'Static Assets Configuration',
        description: 'Static file serving and mount point settings.',
        properties: {
          'enabled': ConfigSchema.boolean(
        description: 'Enable static asset serving.',
        defaultValue: false,
      ),
          'mounts': ConfigSchema.list(
        description: 'List of static mount configurations.',
            items: ConfigSchema.object(
              properties: {
                'route': ConfigSchema.string(
                  description: 'Route prefix clients use to fetch assets.',
                  defaultValue: '/',
                ),
                'prefix': ConfigSchema.string(
                  description: 'Alias for "route".',
                ),
                'disk': ConfigSchema.string(
                  description: 'Storage disk that hosts the assets.',
                ),
                'path': ConfigSchema.string(
                  description: 'Optional subdirectory within the disk.',
                  defaultValue: '',
                ),
                'index': ConfigSchema.string(
                  description:
                  'Default index file served when a directory is requested.',
                ),
                'list_directories': ConfigSchema.boolean(
                  description: 'Allow directory listings for this mount.',
                  defaultValue: false,
                ),
                'directory_listing': ConfigSchema.boolean(
                  description: 'Alias for "list_directories".',
                ),
                'root': ConfigSchema.string(
                  description:
                  'Absolute root directory for this mount (bypasses disks).',
                ),
              },
            ),
            defaultValue: const [],
          ),
        },
      );

  @override
  StaticAssetsConfig fromMap(
    Map<String, dynamic> map, {
    ConfigSpecContext? context,
  }) {
    final enabled =
        parseBoolLike(
          map['enabled'],
          context: 'static.enabled',
          throwOnInvalid: true,
        ) ??
        false;

    final mountsRaw = map['mounts'];
    final List<StaticMountConfig> mounts;
    if (mountsRaw == null) {
      mounts = const <StaticMountConfig>[];
    } else {
      final parsed = parseMapList(
        mountsRaw,
        context: 'static.mounts',
        throwOnInvalid: true,
      );
      mounts = [
        for (var i = 0; i < parsed.length; i += 1)
          StaticMountConfig.fromMap(
            parsed[i],
            contextPath: 'static.mounts[$i]',
          ),
      ];
    }

    return StaticAssetsConfig(enabled: enabled, mounts: mounts);
  }

  @override
  Map<String, dynamic> toMap(StaticAssetsConfig value) {
    return {
      'enabled': value.enabled,
      'mounts': value.mounts
          .map(
            (mount) => {
              'route': mount.route,
              'disk': mount.disk,
              'path': mount.path,
              'index': mount.index,
              'list_directories': mount.listDirectories,
              'file_system': mount.fileSystem,
              'root': mount.root,
            },
          )
          .toList(),
    };
  }
}
