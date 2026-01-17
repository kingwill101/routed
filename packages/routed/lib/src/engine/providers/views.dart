import 'dart:async';

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/config/specs/views.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_manager.dart';
import 'package:routed/src/view/engines/liquid_engine.dart';
import 'package:routed/src/view/view_engine.dart';
import 'package:routed/src/view/engine_manager.dart';

/// Configures view engine defaults driven by configuration/disks.
class ViewServiceProvider extends ServiceProvider with ProvidesDefaultConfig {
  StorageManager? _storageManager;
  file.FileSystem _fallbackFileSystem = const local.LocalFileSystem();
  static const ViewConfigSpec spec = ViewConfigSpec();

  @override
  ConfigDefaults get defaultConfig => ConfigDefaults(
    docs: spec.docs(),
    values: spec.defaultsWithRoot(),
    schemas: spec.schemaWithRoot(),
  );

  @override
  void register(Container container) {
    if (!container.has<EngineConfig>()) {
      return;
    }

    if (!container.has<ViewEngineManager>()) {
      container.instance<ViewEngineManager>(ViewEngineManager());
    }

    _fallbackFileSystem = container.get<EngineConfig>().fileSystem;
    if (container.has<StorageManager>()) {
      _storageManager = container.get<StorageManager>();
    }

    if (container.has<Config>()) {
      _applyConfig(container, container.get<Config>());
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

    _applyConfig(container, container.get<Config>());
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    _applyConfig(container, config, notifyEngine: true);
  }

  void _applyConfig(
    Container container,
    Config config, {
    bool notifyEngine = false,
  }) {
    final engineConfig = container.get<EngineConfig>();
    final resolved = _resolveViewConfig(config, engineConfig);

    final newConfig = engineConfig.copyWith(
      templateDirectory: resolved.directory,
      templateEngine: resolved.viewEngine ?? engineConfig.templateEngine,
      views: resolved.viewConfig,
    );

    container.instance<EngineConfig>(newConfig);

    if (!notifyEngine) {
      return;
    }
    if (!container.has<Engine>()) {
      return;
    }
    container.get<Engine>().updateConfig(newConfig);
  }

  _ResolvedViewConfig _resolveViewConfig(Config config, EngineConfig current) {
    final resolved = spec.resolve(
      config,
      context: ViewConfigContext(config: config, engineConfig: current),
    );

    final configuredDirectory = resolved.directory;
    final cache = resolved.cache;
    final engineName = resolved.engine;
    final diskName = resolved.disk;

    final disk = _storageManager != null
        ? _tryResolveDisk(_storageManager!, diskName)
        : null;

    final fs = disk?.fileSystem ?? _fallbackFileSystem;
    final directory = _resolveDirectory(configuredDirectory, disk, fs, config);

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
    } on StateError {
      return null;
    }
  }

  String _resolveDirectory(
    String configured,
    StorageDisk? disk,
    file.FileSystem fs,
    Config config,
  ) {
    final pathValue = configured.isEmpty ? '' : configured;
    if (disk != null) {
      return disk.resolve(pathValue);
    }
    return _normalizePath(fs, pathValue, config);
  }

  String _normalizePath(file.FileSystem fs, String value, Config config) {
    final pathContext = fs.path;
    final appRoot = config.has('app.root')
        ? config.get<Object?>('app.root')
        : null;
    final base = (appRoot is String && appRoot.trim().isNotEmpty)
        ? pathContext.normalize(appRoot.trim())
        : pathContext.normalize(fs.currentDirectory.path);
    if (value.isEmpty) {
      return base;
    }
    return pathContext.normalize(
      pathContext.isAbsolute(value) ? value : pathContext.join(base, value),
    );
  }

  ViewEngine _createEngine(
    String? engineName,
    String directory,
    file.FileSystem fs,
    ViewEngine? fallback,
  ) {
    final name = (engineName ?? 'liquid').toLowerCase();
    switch (name) {
      case '':
      case 'liquid':
        final scopedFs = _viewFileSystem(fs, directory);
        final root = LiquidRoot(fileSystem: scopedFs);
        return LiquidViewEngine(root: root, directory: directory);
      default:
        return fallback ?? LiquidViewEngine();
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
