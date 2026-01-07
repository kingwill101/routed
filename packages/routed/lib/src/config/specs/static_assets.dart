import 'package:file/file.dart' as file;
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
  Map<String, dynamic> defaults({ConfigSpecContext? context}) {
    return {'enabled': false, 'mounts': const <Map<String, dynamic>>[]};
  }

  @override
  List<ConfigDocEntry> docs({String? pathBase, ConfigSpecContext? context}) {
    final base = pathBase ?? root;
    String path(String segment) => base.isEmpty ? segment : '$base.$segment';

    return <ConfigDocEntry>[
      ConfigDocEntry(
        path: path('enabled'),
        type: 'bool',
        description: 'Enable static asset serving.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: path('mounts'),
        type: 'list<map>',
        description: 'List of static mount configurations.',
        defaultValue: const <Map<String, dynamic>>[],
      ),
      ConfigDocEntry(
        path: path('mounts[].route'),
        type: 'string',
        description: 'Route prefix clients use to fetch assets.',
      ),
      ConfigDocEntry(
        path: path('mounts[].disk'),
        type: 'string',
        description: 'Storage disk that hosts the assets.',
      ),
      ConfigDocEntry(
        path: path('mounts[].path'),
        type: 'string',
        description: 'Optional subdirectory within the disk.',
      ),
      ConfigDocEntry(
        path: path('mounts[].index'),
        type: 'string',
        description: 'Default index file served when a directory is requested.',
      ),
      ConfigDocEntry(
        path: path('mounts[].list_directories'),
        type: 'bool',
        description: 'Allow directory listings for this mount.',
      ),
    ];
  }

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
