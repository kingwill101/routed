import 'dart:async';

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:routed/src/config/specs/static_assets.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/middleware_registry.dart';
import 'package:routed/src/file_handler.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/router/types.dart';
import 'package:routed/src/storage/local_storage_driver.dart';
import 'package:routed/src/storage/storage_manager.dart';

/// Serves configured static assets using the storage abstraction.
class StaticAssetsServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  bool _enabled = false;
  List<_StaticMount> _mounts = const [];
  late file.FileSystem _fallbackFileSystem;
  StorageManager? _storageManager;
  static const StaticAssetsConfigSpec spec = StaticAssetsConfigSpec();

  @override
  ConfigDefaults get defaultConfig {
    final values = spec.defaultsWithRoot();
    values['http'] = {
      'middleware_sources': {
        'routed.static': {
          'global': ['routed.static.assets'],
        },
      },
    };

    return ConfigDefaults(
      docs: [
        const ConfigDocEntry(
          path: 'http.middleware_sources',
          type: 'map',
          description: 'Static asset middleware references registered globally.',
          defaultValue: <String, Object?>{
            'routed.static': <String, Object?>{
              'global': <String>['routed.static.assets'],
            },
          },
        ),
        ...spec.docs(),
      ],
      values: values,
    );
  }

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
    final resolved = spec.resolve(config);
    final mounts = <_StaticMount>[];
    for (final mount in resolved.mounts) {
      mounts.add(
        _StaticMount.fromSpec(
          mount,
          storage: _storageManager,
          fallbackFileSystem: _fallbackFileSystem,
        ),
      );
    }

    final deduped = <String, _StaticMount>{};
    for (final mount in mounts) {
      deduped[mount.route] = mount;
    }

    _enabled = resolved.enabled && deduped.isNotEmpty;
    _mounts = deduped.values.toList(growable: false);
  }
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

  static _StaticMount fromSpec(
    StaticMountConfig config, {
    StorageManager? storage,
    required file.FileSystem fallbackFileSystem,
  }) {
    final route = _normalizeRoute(config.route);
    final normalizedDiskName =
        config.disk == null || config.disk!.isEmpty ? null : config.disk;
    final relativePath = config.path;
    final indexFile = config.index;
    final listDirectories = config.listDirectories;

    final customFs = config.fileSystem;
    file.FileSystem effectiveFs;
    String absolutePath;

    if (customFs != null) {
      effectiveFs = customFs;
      final fsPath = effectiveFs.path;
      final rootValue = config.root ?? '';
      final current = effectiveFs.currentDirectory.path;
      final resolvedRoot = rootValue.isEmpty
          ? current
          : fsPath.normalize(
              fsPath.isAbsolute(rootValue)
                  ? rootValue
                  : fsPath.join(current, rootValue),
            );
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
    }

    final dir = Dir(
      absolutePath,
      listDirectory: listDirectories,
      fileSystem: effectiveFs,
    );
    final handler = FileHandler.fromDir(dir);
    final rootPath = _resolveRootPath(dir);

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
    final pathContext = _dir.fileSystem.path;
    final match = _match(requestPath);
    if (match == null) {
      return false;
    }

    final relative = match.relativePath;
    final isDirectoryRequest = match.isDirectory;

    if (isDirectoryRequest && indexFile != null) {
      final indexTarget = relative.isEmpty
          ? indexFile!
          : pathContext.join(relative, indexFile!);
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
        : _dir.fileSystem.path.join(_rootPath, relativePath);
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
    final pathContext = fs.path;
    final currentDir = pathContext.normalize(fs.currentDirectory.path);
    return pathContext.normalize(
      pathContext.isAbsolute(dir.path)
          ? dir.path
          : pathContext.join(currentDir, dir.path),
    );
  }
}

class _MatchResult {
  const _MatchResult(this.relativePath, this.isDirectory);

  final String relativePath;
  final bool isDirectory;
}
