import 'dart:async';

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:path/path.dart' as p;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/file_handler.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/storage/storage_manager.dart';

/// Serves configured static assets using the storage abstraction.
class StaticAssetsServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  bool _enabled = false;
  List<_StaticMount> _mounts = const [];
  late file.FileSystem _fallbackFileSystem;
  StorageManager? _storageManager;

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    values: {
      'http': {
        'middleware_sources': {
          'routed.static': {
            'global': ['routed.static.assets'],
          },
        },
      },
    },
    docs: [
      ConfigDocEntry(
        path: 'static.enabled',
        type: 'bool',
        description: 'Enable static asset serving.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'static.mounts',
        type: 'list<map>',
        description: 'List of static mount configurations.',
        defaultValue: <Map<String, dynamic>>[],
      ),
      ConfigDocEntry(
        path: 'static.mounts[].route',
        type: 'string',
        description: 'Route prefix clients use to fetch assets.',
      ),
      ConfigDocEntry(
        path: 'static.mounts[].disk',
        type: 'string',
        description: 'Storage disk that hosts the assets.',
      ),
      ConfigDocEntry(
        path: 'static.mounts[].path',
        type: 'string',
        description: 'Optional subdirectory within the disk.',
      ),
      ConfigDocEntry(
        path: 'static.mounts[].index',
        type: 'string',
        description: 'Default index file served when a directory is requested.',
      ),
      ConfigDocEntry(
        path: 'static.mounts[].list_directories',
        type: 'bool',
        description: 'Allow directory listings for this mount.',
      ),
      ConfigDocEntry(
        path: 'http.features.static.enabled',
        type: 'bool',
        description: 'Feature toggle for legacy static asset middleware.',
        defaultValue: false,
      ),
      ConfigDocEntry(
        path: 'http.features.static.root',
        type: 'string',
        description: 'Legacy static asset root directory.',
        defaultValue: 'public',
      ),
      ConfigDocEntry(
        path: 'http.features.static.prefix',
        type: 'string',
        description: 'Legacy prefix for static middleware.',
        defaultValue: '/',
      ),
      ConfigDocEntry(
        path: 'http.features.static.index',
        type: 'string',
        description: 'Fallback index file used by the legacy static feature.',
        defaultValue: 'index.html',
      ),
      ConfigDocEntry(
        path: 'http.features.static.list_directories',
        type: 'bool',
        description:
            'Whether the legacy static feature exposes directory listings.',
        defaultValue: false,
      ),
    ],
  );

  @override
  void register(Container container) {
    _fallbackFileSystem = container.has<EngineConfig>()
        ? container.get<EngineConfig>().fileSystem
        : const local.LocalFileSystem();

    if (container.has<StorageManager>()) {
      _storageManager = container.get<StorageManager>();
    }

    final registry = container.get<MiddlewareRegistry>();
    registry.register('routed.static.assets', (_) => _staticMiddleware);

    if (container.has<Config>()) {
      _applyConfig(container.get<Config>());
    }
  }

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Config>()) {
      return;
    }

    if (container.has<EngineConfig>()) {
      _fallbackFileSystem = container.get<EngineConfig>().fileSystem;
    }

    if (container.has<StorageManager>()) {
      _storageManager = container.get<StorageManager>();
    }

    _applyConfig(container.get<Config>());
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    _applyConfig(config);
  }

  Middleware get _staticMiddleware {
    return (EngineContext ctx, Next next) async {
      if (!_enabled) {
        return await next();
      }

      final method = ctx.request.method;
      if (method != 'GET' && method != 'HEAD') {
        return await next();
      }

      final path = ctx.request.uri.path;
      for (final mount in _mounts) {
        final served = await mount.tryServe(ctx, path);
        if (served) {
          return ctx.response;
        }
      }

      return await next();
    };
  }

  void _applyConfig(Config config) {
    final resolved = _resolveStaticConfig(config);
    _enabled = resolved.enabled && resolved.mounts.isNotEmpty;
    _mounts = resolved.mounts;
  }

  _StaticConfig _resolveStaticConfig(Config config) {
    var enabled =
        parseBoolLike(
          config.get('static.enabled'),
          context: 'static.enabled',
          stringMappings: const {'true': true, 'false': false},
        ) ??
        false;
    final mounts = <_StaticMount>[];

    void addMount(Map<String, dynamic> node, int index) {
      final mount = _StaticMount.fromConfig(
        node,
        contextPath: 'static.mounts[$index]',
        storage: _storageManager,
        fallbackFileSystem: _fallbackFileSystem,
      );
      if (mount != null) {
        mounts.add(mount);
      }
    }

    final staticNode = config.get('static');
    if (staticNode != null && staticNode is! Map) {
      throw ProviderConfigException('static must be a map');
    }

    final mountsNode = config.get('static.mounts');
    if (mountsNode is Iterable) {
      var idx = 0;
      for (final entry in mountsNode) {
        if (entry is Map || entry is Config) {
          final mountSource = entry as Object;
          addMount(stringKeyedMap(mountSource, 'static.mounts[$idx]'), idx);
        } else {
          throw ProviderConfigException('static.mounts[$idx] must be a map');
        }
        idx++;
      }
    } else if (mountsNode != null) {
      throw ProviderConfigException('static.mounts must be a list');
    }

    final legacyRaw = config.get('http.features.static');
    if (legacyRaw != null) {
      final legacy = stringKeyedMap(
        legacyRaw as Object,
        'http.features.static',
      );
      final legacyEnabled = parseBoolLike(
        legacy['enabled'],
        context: 'http.features.static.enabled',
        stringMappings: const {'true': true, 'false': false},
        throwOnInvalid: false,
      );
      if (legacyEnabled == true) {
        enabled = true;
      }
      addMount({
        'route': legacy['prefix'] ?? '/',
        'path': legacy['root'],
        'index': legacy['index'],
        'list_directories': legacy['list_directories'],
      }, mounts.length);
    }

    final deduped = <String, _StaticMount>{};
    for (final mount in mounts) {
      deduped[mount.route] = mount;
    }

    return _StaticConfig(
      enabled: enabled,
      mounts: deduped.values.toList(growable: false),
    );
  }
}

class _StaticConfig {
  const _StaticConfig({required this.enabled, required this.mounts});

  final bool enabled;
  final List<_StaticMount> mounts;
}

class _StaticMount {
  _StaticMount._(
    this.route,
    this._dir,
    this._handler,
    this._listDirectories,
    this.indexFile,
    this._rootPath,
  );

  final String route;
  final Dir _dir;
  final FileHandler _handler;
  final bool _listDirectories;
  final String? indexFile;
  final String _rootPath;

  static _StaticMount? fromConfig(
    Map<String, dynamic> node, {
    StorageManager? storage,
    required file.FileSystem fallbackFileSystem,
    required String contextPath,
  }) {
    final hasRouteKey = node.containsKey('route') || node.containsKey('prefix');
    final rawRoute =
        parseStringLike(
          node.containsKey('route') ? node['route'] : node['prefix'],
          context: '$contextPath.route',
          allowEmpty: true,
          coerceNonString: false,
          throwOnInvalid: hasRouteKey,
        ) ??
        '/';
    final route = _normalizeRoute(rawRoute);

    final diskName = parseStringLike(
      node['disk'],
      context: '$contextPath.disk',
      allowEmpty: false,
      coerceNonString: false,
      throwOnInvalid: node.containsKey('disk'),
    );
    final pathValue = node.containsKey('path')
        ? node['path']
        : node['directory'];
    final relativePath =
        parseStringLike(
          pathValue,
          context: '$contextPath.path',
          allowEmpty: true,
          coerceNonString: true,
          throwOnInvalid: pathValue != null,
        ) ??
        '';

    final indexToken = parseStringLike(
      node['index'],
      context: '$contextPath.index',
      allowEmpty: true,
      coerceNonString: true,
      throwOnInvalid: false,
    );
    final indexFile = indexToken == null || indexToken.isEmpty
        ? null
        : indexToken;

    final listDirectories =
        (parseBoolLike(
              node['list_directories'],
              context: '$contextPath.list_directories',
              stringMappings: const {'true': true, 'false': false},
              throwOnInvalid: false,
            ) ??
            false) ||
        (parseBoolLike(
              node['directory_listing'],
              context: '$contextPath.directory_listing',
              stringMappings: const {'true': true, 'false': false},
              throwOnInvalid: false,
            ) ??
            false);

    final normalizedDiskName = diskName == null || diskName.isEmpty
        ? null
        : diskName;

    final customFs = node['file_system'];
    file.FileSystem effectiveFs;
    String absolutePath;
    String rootPath;

    if (customFs != null) {
      if (customFs is! file.FileSystem) {
        throw ProviderConfigException(
          '$contextPath.file_system must implement FileSystem',
        );
      }
      effectiveFs = customFs;
      final fsPath = effectiveFs.path;
      final rootValue =
          parseStringLike(
            node['root'],
            context: '$contextPath.root',
            allowEmpty: true,
            coerceNonString: true,
            throwOnInvalid: false,
          ) ??
          '';
      final current = effectiveFs.currentDirectory.path;
      final resolvedRoot = rootValue.isEmpty
          ? current
          : fsPath.normalize(
              fsPath.isAbsolute(rootValue)
                  ? rootValue
                  : fsPath.join(current, rootValue),
            );
      rootPath = resolvedRoot;
      absolutePath = relativePath.isEmpty
          ? resolvedRoot
          : fsPath.normalize(fsPath.join(resolvedRoot, relativePath));
    } else {
      final disk = _resolveDisk(
        storage,
        normalizedDiskName,
        fallbackFileSystem,
      );
      effectiveFs = disk.fileSystem;
      absolutePath = disk.resolve(relativePath);
      rootPath = disk.resolve('');
    }

    final dir = Dir(
      absolutePath,
      listDirectory: listDirectories,
      fileSystem: effectiveFs,
    );
    final handler = FileHandler.fromDir(dir);
    rootPath = _resolveRootPath(dir);

    return _StaticMount._(
      route,
      dir,
      handler,
      listDirectories,
      indexFile,
      rootPath,
    );
  }

  Future<bool> tryServe(EngineContext ctx, String requestPath) async {
    final match = _match(requestPath);
    if (match == null) {
      return false;
    }

    final relative = match.relativePath;
    final isDirectoryRequest = match.isDirectory;

    if (isDirectoryRequest && indexFile != null) {
      final indexTarget = relative.isEmpty
          ? indexFile!
          : p.join(relative, indexFile!);
      if (await _entityExists(indexTarget)) {
        await _handler.serveFile(ctx, indexTarget);
        return true;
      }
    }

    if (relative.isEmpty) {
      if (_listDirectories) {
        await _handler.serveFile(ctx, relative);
        return true;
      }
      return false;
    }

    if (!await _entityExists(relative)) {
      if (isDirectoryRequest && _listDirectories) {
        await _handler.serveFile(ctx, relative);
        return true;
      }
      return false;
    }

    await _handler.serveFile(ctx, relative);
    return true;
  }

  _MatchResult? _match(String path) {
    if (!path.startsWith('/')) {
      path = '/$path';
    }

    if (route == '/') {
      final trimmed = path.length == 1 ? '' : path.substring(1);
      final isDirectory = path == '/' || path.endsWith('/');
      final normalized = isDirectory && trimmed.endsWith('/')
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
      return _MatchResult(normalized, isDirectory);
    }

    if (path == route) {
      return const _MatchResult('', true);
    }

    final routeWithSlash = '$route/';
    if (!path.startsWith(routeWithSlash)) {
      return null;
    }

    final remaining = path.substring(routeWithSlash.length);
    final isDirectory = remaining.isEmpty || path.endsWith('/');
    final normalized = isDirectory && remaining.endsWith('/')
        ? remaining.substring(0, remaining.length - 1)
        : remaining;

    return _MatchResult(normalized, isDirectory);
  }

  Future<bool> _entityExists(String relativePath) async {
    final fullPath = relativePath.isEmpty
        ? _rootPath
        : p.join(_rootPath, relativePath);
    try {
      final stat = await _dir.fileSystem.stat(fullPath);
      return stat.type != file.FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }

  static StorageDisk _resolveDisk(
    StorageManager? storage,
    String? diskName,
    file.FileSystem fallback,
  ) {
    if (storage == null) {
      return LocalStorageDisk(root: '', fileSystem: fallback);
    }
    try {
      return storage.disk(diskName);
    } on StateError {
      return LocalStorageDisk(root: '', fileSystem: fallback);
    }
  }

  static String _normalizeRoute(String value) {
    var route = value.trim();
    if (route.isEmpty) return '/';
    if (!route.startsWith('/')) {
      route = '/$route';
    }
    if (route.length > 1 && route.endsWith('/')) {
      route = route.substring(0, route.length - 1);
    }
    return route;
  }

  static String _resolveRootPath(Dir dir) {
    final fs = dir.fileSystem;
    final currentDir = p.normalize(fs.currentDirectory.path);
    return p.normalize(
      p.isAbsolute(dir.path) ? dir.path : p.join(currentDir, dir.path),
    );
  }
}

class _MatchResult {
  const _MatchResult(this.relativePath, this.isDirectory);

  final String relativePath;
  final bool isDirectory;
}
