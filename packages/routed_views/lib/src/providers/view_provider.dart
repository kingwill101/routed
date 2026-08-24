import 'dart:async';

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:routed_core/routed_core.dart'
    show
        Container,
        EngineConfig,
        ProvidesTypedConfiguration,
        ServiceProvider,
        ViewConfig;
import 'package:routed_views/src/config.dart';
import 'package:routed_views/src/view/engine_manager.dart';
import 'package:routed_views/src/view/engines/liquid_engine.dart';
import 'package:routed_views/src/view/view_engine.dart';
import 'package:routed_views/src/view/view_extensions.dart';
import 'package:server_storage/server_storage.dart';

/// Configures the view engine from an immutable typed configuration.
class ViewServiceProvider extends ServiceProvider
    with ProvidesTypedConfiguration<RoutedViewConfig> {
  /// Creates the view provider with [configuration], or Liquid defaults.
  ViewServiceProvider([RoutedViewConfig? configuration])
    : configuration = configuration ?? RoutedViewConfig();

  @override
  final RoutedViewConfig configuration;

  StorageManager? _storageManager;
  file.FileSystem _fallbackFileSystem = const local.LocalFileSystem();

  @override
  void register(Container container) {
    if (!container.has<EngineConfig>()) {
      return;
    }

    if (!container.has<ViewExtensionRegistry>()) {
      container.instance<ViewExtensionRegistry>(ViewExtensionRegistry.instance);
    }

    if (!container.has<ViewEngineManager>()) {
      container.instance<ViewEngineManager>(ViewEngineManager());
    }

    _fallbackFileSystem = container.get<EngineConfig>().fileSystem;
  }

  @override
  Future<void> boot(Container container) async {
    if (!container.has<EngineConfig>()) {
      return;
    }

    if (container.has<EngineConfig>()) {
      _fallbackFileSystem = container.get<EngineConfig>().fileSystem;
    }
    if (container.has<StorageManager>()) {
      _storageManager = await container.make<StorageManager>();
    }

    _applyConfig(container, configuration);
  }

  void _applyConfig(Container container, RoutedViewConfig config) {
    final engineConfig = container.get<EngineConfig>();
    final resolved = _resolveViewConfig(config, engineConfig);

    final newConfig = engineConfig.copyWith(
      templateDirectory: resolved.directory,
      templateEngine: resolved.viewEngine ?? engineConfig.templateEngine,
      views: resolved.viewConfig,
    );

    container.instance<EngineConfig>(newConfig);

    if (resolved.viewEngine != null && container.has<ViewEngineManager>()) {
      container.get<ViewEngineManager>().register(resolved.viewEngine!);
    }
  }

  _ResolvedViewConfig _resolveViewConfig(
    RoutedViewConfig config,
    EngineConfig current,
  ) {
    final configuredDirectory = config.directory;
    final cache = config.cache;
    final engineName = config.engine;
    final diskName = config.disk;

    final disk = _storageManager != null
        ? _tryResolveDisk(_storageManager!, diskName)
        : null;

    final fs = disk?.fileSystem ?? _fallbackFileSystem;
    final directory = _resolveDirectory(configuredDirectory, disk, fs);

    final viewEngine = _createEngine(
      engineName,
      directory,
      fs,
      current.templateEngine,
    );

    final viewConfig = ViewConfig(viewPath: directory, cache: cache);

    return _ResolvedViewConfig(
      directory: directory,
      viewEngine: viewEngine,
      viewConfig: viewConfig,
    );
  }

  StorageDisk? _tryResolveDisk(StorageManager manager, String? name) {
    if (name == null || name.isEmpty) {
      return null;
    }
    try {
      return manager.disk(name);
    } on Object catch (error) {
      if (error is StateError) {
        return null;
      }
      rethrow;
    }
  }

  String _resolveDirectory(
    String configured,
    StorageDisk? disk,
    file.FileSystem fs,
  ) {
    final pathValue = configured.isEmpty ? '' : configured;
    if (disk != null) {
      return disk.resolve(pathValue);
    }
    return _normalizePath(fs, pathValue);
  }

  String _normalizePath(file.FileSystem fs, String value) {
    final pathContext = fs.path;
    final base = pathContext.normalize(fs.currentDirectory.path);
    if (value.isEmpty) {
      return base;
    }
    return pathContext.normalize(
      pathContext.isAbsolute(value) ? value : pathContext.join(base, value),
    );
  }

  ViewEngine _createEngine(
    String engineName,
    String directory,
    file.FileSystem fs,
    Object? fallback,
  ) {
    final name = engineName.toLowerCase();
    switch (name) {
      case '':
      case 'liquid':
        final scopedFs = _viewFileSystem(fs, directory);
        final root = LiquidRoot(fileSystem: scopedFs);
        return LiquidViewEngine(root: root, directory: directory);
      default:
        return fallback is ViewEngine ? fallback : LiquidViewEngine();
    }
  }

  file.FileSystem _viewFileSystem(file.FileSystem fs, String directory) {
    return _ScopedFileSystem(fs, directory);
  }
}

class _ScopedFileSystem extends file.ForwardingFileSystem {
  _ScopedFileSystem(super.delegate, String initialDirectory)
    : _currentDirectory = _normalizePath(delegate, initialDirectory);

  String _currentDirectory;

  @override
  file.Directory get currentDirectory => delegate.directory(_currentDirectory);

  @override
  set currentDirectory(dynamic path) {
    if (path is file.Directory) {
      _currentDirectory = _normalizePath(delegate, path.path);
      return;
    }
    if (path is String) {
      _currentDirectory = _normalizePath(delegate, path);
      return;
    }
    throw ArgumentError('Invalid type for "path": ${path?.runtimeType}');
  }
}

String _normalizePath(file.FileSystem fs, String value) {
  if (value.isEmpty) return fs.currentDirectory.path;
  final pathContext = fs.path;
  if (pathContext.isAbsolute(value)) {
    return pathContext.normalize(value);
  }
  return pathContext.normalize(
    pathContext.join(fs.currentDirectory.path, value),
  );
}

class _ResolvedViewConfig {
  _ResolvedViewConfig({
    required this.directory,
    required this.viewEngine,
    required this.viewConfig,
  });

  final String directory;
  final ViewEngine? viewEngine;
  final ViewConfig viewConfig;
}
