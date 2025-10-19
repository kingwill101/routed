import 'dart:async';

import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:path/path.dart' as p;
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/provider/provider.dart';
import 'package:routed/src/storage/storage_manager.dart';
import 'package:routed/src/view/engines/liquid_engine.dart';
import 'package:routed/src/view/view_engine.dart';

/// Configures view engine defaults driven by configuration/disks.
class ViewServiceProvider extends ServiceProvider with ProvidesDefaultConfig {
  StorageManager? _storageManager;
  file.FileSystem _fallbackFileSystem = const local.LocalFileSystem();

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    docs: [
      ConfigDocEntry(
        path: 'view.engine',
        type: 'string',
        description: 'View engine identifier (e.g. liquid).',
        defaultValue: 'liquid',
      ),
      ConfigDocEntry(
        path: 'view.directory',
        type: 'string',
        description: 'Path to templates relative to app root or disk.',
        defaultValue: 'views',
      ),
      ConfigDocEntry(
        path: 'view.cache',
        type: 'bool',
        description: 'Enable template caching in production environments.',
        defaultValue: true,
      ),
      ConfigDocEntry(
        path: 'view.disk',
        type: 'string|null',
        description: 'Optional storage disk to source templates from.',
        defaultValue: null,
      ),
    ],
  );

  @override
  void register(Container container) {
    if (!container.has<EngineConfig>()) {
      return;
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
    final viewNode = config.get('view');
    if (viewNode != null && viewNode is! Map) {
      throw ProviderConfigException('view must be a map');
    }

    String configuredDirectory = current.templateDirectory;
    bool cache = current.views.cache;
    String? engineName;
    String? diskName;

    final directoryNode = config.get('view.directory');
    if (directoryNode != null) {
      if (directoryNode is! String) {
        throw ProviderConfigException('view.directory must be a string');
      }
      if (directoryNode.isNotEmpty) {
        configuredDirectory = directoryNode;
      }
    }

    final cacheNode = config.get('view.cache');
    if (cacheNode != null) {
      cache = _readBool(cacheNode as Object, 'view.cache');
    }

    final engineNode = config.get('view.engine');
    if (engineNode != null) {
      if (engineNode is! String) {
        throw ProviderConfigException('view.engine must be a string');
      }
      final trimmed = engineNode.trim();
      if (trimmed.isEmpty) {
        throw ProviderConfigException('view.engine must be a string');
      }
      engineName = trimmed;
    }

    final diskNode = config.get('view.disk');
    if (diskNode != null) {
      if (diskNode is! String) {
        throw ProviderConfigException('view.disk must be a string');
      }
      final trimmed = diskNode.trim();
      if (trimmed.isEmpty) {
        throw ProviderConfigException('view.disk must be a string');
      }
      diskName = trimmed;
    }

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

  bool _readBool(Object value, String context) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
    throw ProviderConfigException('$context must be a boolean');
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
  ) {
    final pathValue = configured.isEmpty ? '' : configured;
    if (disk != null) {
      return disk.resolve(pathValue);
    }
    return _normalizePath(fs, pathValue);
  }

  String _normalizePath(file.FileSystem fs, String value) {
    final base = fs.currentDirectory.path;
    if (value.isEmpty) {
      return p.normalize(base);
    }
    return p.normalize(p.isAbsolute(value) ? value : p.join(base, value));
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
        final root = LiquidRoot(fileSystem: fs);
        _setCurrentDirectory(fs, directory);
        return LiquidViewEngine(root: root);
      default:
        return fallback ?? LiquidViewEngine();
    }
  }

  void _setCurrentDirectory(file.FileSystem fs, String directory) {
    if (directory.isEmpty) return;
    final dir = fs.directory(directory);
    if (!dir.existsSync()) {
      return;
    }
    try {
      fs.currentDirectory = dir.path;
    } catch (_) {}
  }
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
