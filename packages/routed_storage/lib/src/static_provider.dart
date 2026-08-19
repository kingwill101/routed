import 'package:path/path.dart' as p;
import 'package:routed_core/routed_core.dart';
import 'package:server_storage/server_storage.dart';

import 'engine_static_file_sink.dart';

/// Immutable configuration for [RoutedStaticProvider].
class StaticConfig implements ValidatableConfiguration {
  StaticConfig({this.enabled = false, List<StaticMountConfig>? mounts})
    : mounts = List<StaticMountConfig>.unmodifiable(
        mounts ?? const <StaticMountConfig>[],
      );

  final bool enabled;
  final List<StaticMountConfig> mounts;

  @override
  void validate(ConfigValidationContext context) {
    for (var index = 0; index < mounts.length; index++) {
      final mount = mounts[index];
      final path = 'mounts[$index]';
      final route = _normalizeStaticRoute(mount.route);
      context.require(
        route.trim().isNotEmpty,
        '$path.route',
        'route is required',
      );
      context.require(
        !route.contains(':') && !route.contains('*'),
        '$path.route',
        'route cannot contain URL parameters',
      );
      context.require(
        mount.disk != null || mount.root != null,
        path,
        'mount requires disk or root',
      );
      if (mount.disk != null) {
        context.require(
          mount.disk!.trim().isNotEmpty,
          '$path.disk',
          'disk name cannot be empty',
        );
      }
      if (mount.root != null) {
        context.require(
          mount.root!.trim().isNotEmpty,
          '$path.root',
          'root cannot be empty',
        );
      }
      context.require(
        _isSafeStaticRelativePath(mount.path),
        '$path.path',
        'path must stay within the mount root',
      );
      context.require(
        _isSafeStaticRelativePath(mount.indexFile),
        '$path.indexFile',
        'index file must stay within the mount root',
      );
    }
  }
}

/// Installs declarative static mounts from [configuration].
class RoutedStaticProvider extends ServiceProvider
    with ProvidesTypedConfiguration<StaticConfig> {
  RoutedStaticProvider([StaticConfig? configuration])
    : configuration = configuration ?? StaticConfig();

  @override
  final StaticConfig configuration;

  final List<Object> _registeredRoutes = [];

  @override
  void register(Container container) {}

  @override
  Future<void> boot(Container container) async {
    if (!configuration.enabled ||
        !container.has<Engine>() ||
        !container.has<StorageManager>()) {
      return;
    }
    final engine = container.get<Engine>();
    final storage = await container.make<StorageManager>();
    for (final mount in configuration.mounts) {
      _registerMount(engine, storage, mount);
    }
    engine.invalidateRoutes();
  }

  void _registerMount(
    Engine engine,
    StorageManager storage,
    StaticMountConfig mount,
  ) {
    final handler = FileHandler.fromDir(_resolveDir(storage, mount));
    final router = engine.defaultRouter;
    final route = _normalizeRoute(mount.route);
    final before = router.routes.length;

    Future<Response> serve(EngineContext context, [String path = '']) async {
      await handler.serveToContext(context, path);
      return context.response;
    }

    router.get(route, (context) => serve(context));
    router.head(route, (context) => serve(context));
    final wildcard = p.posix.join(route, '{*filepath}');
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

  String _normalizeRoute(String route) {
    final normalized = route.startsWith('/') ? route : '/$route';
    if (normalized.length > 1 && normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}

String _normalizeStaticRoute(String route) {
  final normalized = route.startsWith('/') ? route : '/$route';
  if (normalized.length > 1 && normalized.endsWith('/')) {
    return normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _isSafeStaticRelativePath(String value) {
  if (value.isEmpty) return true;
  final normalized = p.posix.normalize(value);
  return !p.posix.isAbsolute(value) &&
      normalized != '..' &&
      !normalized.startsWith('../');
}

final class StaticMountConfig {
  const StaticMountConfig({
    required this.route,
    this.disk,
    this.root,
    this.path = '',
    this.indexFile = 'index.html',
    this.listDirectories = false,
  });

  final String route;
  final String? disk;
  final String? root;
  final String path;
  final String indexFile;
  final bool listDirectories;
}
