import 'package:path/path.dart' as p;
import 'package:routed_core/routed_core.dart';
import 'package:server_storage/server_storage.dart';

import 'engine_static_file_sink.dart';

/// Installs declarative static mounts from `static.*` configuration.
class RoutedStaticProvider extends ServiceProvider with ProvidesDefaultConfig {
  List<Object> _registeredRoutes = [];

  @override
  void register(Container container) {}

  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    values: {
      'static': {'enabled': false, 'mounts': <Map<String, Object?>>[]},
    },
    docs: const [
      ConfigDocEntry(
        path: 'static.enabled',
        type: 'bool',
        description: 'Enable declarative static file mounts.',
      ),
      ConfigDocEntry(
        path: 'static.mounts',
        type: 'list',
        description: 'Storage-backed static mount definitions.',
      ),
    ],
  );

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Engine>() ||
        !container.has<Config>() ||
        !container.has<StorageManager>()) {
      return;
    }
    _apply(
      container.get<Engine>(),
      container.get<Config>(),
      await container.make<StorageManager>(),
    );
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    if (!container.has<Engine>() || !container.has<StorageManager>()) return;
    _apply(
      container.get<Engine>(),
      config,
      await container.make<StorageManager>(),
    );
  }

  void _apply(Engine engine, Config config, StorageManager storage) {
    _removeRoutes(engine);
    if (!config.getBool('static.enabled')) return;

    final mounts = parseMapList(
      config.get<Object?>('static.mounts'),
      context: 'static.mounts',
    );
    for (var index = 0; index < mounts.length; index++) {
      _registerMount(engine, storage, _parseMount(mounts[index], index));
    }
    engine.invalidateRoutes();
  }

  StaticMountConfig _parseMount(Map<String, dynamic> values, int index) {
    final context = 'static.mounts[$index]';
    final route = parseStringLike(
      values['route'] ?? values['prefix'],
      context: '$context.route',
    );
    if (route == null) {
      throw ProviderConfigException('$context.route is required');
    }
    final normalizedRoute = _normalizeRoute(route);
    if (normalizedRoute.contains(':') || normalizedRoute.contains('*')) {
      throw ProviderConfigException(
        '$context.route cannot contain URL parameters',
      );
    }

    final disk = parseStringLike(
      values['disk'],
      context: '$context.disk',
      allowEmpty: true,
    );
    final root = parseStringLike(
      values['root'],
      context: '$context.root',
      allowEmpty: false,
    );
    if (disk == null && root == null) {
      throw ProviderConfigException('$context requires disk or root');
    }

    final path =
        parseStringLike(
          values['path'],
          context: '$context.path',
          allowEmpty: true,
        ) ??
        '';
    _validateRelativePath(path, '$context.path');
    final indexFile =
        parseStringLike(
          values['index'],
          context: '$context.index',
          allowEmpty: true,
        ) ??
        'index.html';
    _validateRelativePath(indexFile, '$context.index');
    final listDirectories =
        parseBoolLike(
          values['list_directories'] ?? values['directory_listing'],
          context: '$context.list_directories',
        ) ??
        false;

    return StaticMountConfig(
      route: normalizedRoute,
      disk: disk,
      root: root,
      path: path,
      indexFile: indexFile,
      listDirectories: listDirectories,
    );
  }

  void _registerMount(
    Engine engine,
    StorageManager storage,
    StaticMountConfig mount,
  ) {
    final handler = FileHandler.fromDir(_resolveDir(storage, mount));
    final router = engine.defaultRouter;
    final before = router.routes.length;

    Future<Response> serve(EngineContext context, [String path = '']) async {
      await handler.serveToContext(context, path);
      return context.response;
    }

    router.get(mount.route, (context) => serve(context));
    router.head(mount.route, (context) => serve(context));
    final wildcard = p.posix.join(mount.route, '{*filepath}');
    router.get(
      wildcard,
      (context) => serve(context, context.param('filepath')?.toString() ?? ''),
    );
    router.head(
      wildcard,
      (context) => serve(context, context.param('filepath')?.toString() ?? ''),
    );

    _registeredRoutes.addAll(router.routes.skip(before));
  }

  Dir _resolveDir(StorageManager storage, StaticMountConfig mount) {
    if (mount.root != null) {
      return Dir(
        p.join(mount.root!, mount.path),
        indexFile: mount.indexFile,
        listDirectory: mount.listDirectories,
      );
    }

    final disk = storage.disk(mount.disk);
    return Dir(
      disk.resolve(mount.path),
      fileSystem: disk.fileSystem,
      indexFile: mount.indexFile,
      listDirectory: mount.listDirectories,
    );
  }

  void _removeRoutes(Engine engine) {
    if (_registeredRoutes.isEmpty) return;
    engine.defaultRouter.routes.removeWhere(_registeredRoutes.contains);
    _registeredRoutes = [];
    engine.invalidateRoutes();
  }

  String _normalizeRoute(String route) {
    final normalized = route.startsWith('/') ? route : '/$route';
    if (normalized.length > 1 && normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  void _validateRelativePath(String value, String context) {
    if (value.isEmpty) return;
    final normalized = p.posix.normalize(value);
    if (p.posix.isAbsolute(value) ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw ProviderConfigException('$context must stay within the mount root');
    }
  }
}

final class StaticMountConfig {
  const StaticMountConfig({
    required this.route,
    required this.disk,
    required this.root,
    required this.path,
    required this.indexFile,
    required this.listDirectories,
  });

  final String route;
  final String? disk;
  final String? root;
  final String path;
  final String indexFile;
  final bool listDirectories;
}
