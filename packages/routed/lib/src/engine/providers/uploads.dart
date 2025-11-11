import 'dart:async';

import 'package:collection/collection.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/provider/provider.dart';

/// Configures multipart upload defaults.
class UploadsServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  Engine? _engine;

  static const _setEquality = SetEquality<String>();

  @override
  ConfigDefaults get defaultConfig => const ConfigDefaults(
    docs: [
      ConfigDocEntry(
        path: 'uploads.max_memory',
        type: 'int',
        description: 'Maximum in-memory bytes before buffering to disk.',
        defaultValue: 32 * 1024 * 1024,
      ),
      ConfigDocEntry(
        path: 'uploads.max_file_size',
        type: 'int',
        description: 'Maximum accepted upload size in bytes.',
        defaultValue: 10 * 1024 * 1024,
      ),
      ConfigDocEntry(
        path: 'uploads.max_disk_usage',
        type: 'int',
        description:
            'Maximum cumulative bytes written to disk per request before uploads are rejected.',
        defaultValue: 32 * 1024 * 1024,
      ),
      ConfigDocEntry(
        path: 'uploads.allowed_extensions',
        type: 'list<string>',
        description: 'Whitelisted file extensions for uploads.',
        defaultValue: ['jpg', 'jpeg', 'png', 'gif', 'pdf'],
      ),
      ConfigDocEntry(
        path: 'uploads.directory',
        type: 'string',
        description: 'Directory where uploaded files are stored.',
        defaultValue: 'uploads',
      ),
      ConfigDocEntry(
        path: 'uploads.file_permissions',
        type: 'int',
        description: 'Permissions to apply to uploaded files.',
        defaultValue: 750,
      ),
    ],
  );

  @override
  void register(Container container) {
    if (!container.has<Config>() || !container.has<EngineConfig>()) {
      return;
    }
    final appConfig = container.get<Config>();
    final engineConfig = container.get<EngineConfig>();
    final resolved = _resolveMultipartConfig(appConfig, engineConfig.multipart);

    if (_multipartEquals(engineConfig.multipart, resolved)) {
      return;
    }
    if (container.has<Engine>()) {
      final engine = container.get<Engine>();
      _applyMultipartConfig(engine, appConfig);
    } else {
      container.instance<EngineConfig>(
        engineConfig.copyWith(multipart: resolved),
      );
    }
  }

  @override
  Future<void> boot(Container container) async {
    if (!container.has<Config>()) {
      return;
    }

    if (container.has<Engine>()) {
      _engine = await container.make<Engine>();
      _applyMultipartConfig(_engine!, container.get<Config>());
    }
  }

  @override
  Future<void> onConfigReload(Container container, Config config) async {
    final engine =
        _engine ??
        (container.has<Engine>() ? await container.make<Engine>() : null);
    if (engine != null) {
      _applyMultipartConfig(engine, config);
    }
  }

  void _applyMultipartConfig(Engine engine, Config config) {
    final current = engine.config;
    final resolved = _resolveMultipartConfig(config, current.multipart);
    if (_multipartEquals(current.multipart, resolved)) {
      return;
    }
    engine.updateConfig(current.copyWith(multipart: resolved));
  }

  MultipartConfig _resolveMultipartConfig(
    Config config,
    MultipartConfig existing,
  ) {
    final merged = mergeConfigCandidates([
      ConfigMapCandidate.fromConfig(config, 'uploads'),
    ]);
    merged.remove('enabled');

    final maxMemory =
        parseIntLike(merged['max_memory'], context: 'uploads.max_memory') ??
        existing.maxMemory;
    final maxFileSize =
        parseIntLike(
          merged['max_file_size'],
          context: 'uploads.max_file_size',
        ) ??
        existing.maxFileSize;
    final maxDiskUsage =
        parseIntLike(
          merged['max_disk_usage'],
          context: 'uploads.max_disk_usage',
        ) ??
        existing.maxDiskUsage;
    final allowedExtensions =
        parseStringSet(
          merged['allowed_extensions'],
          context: 'uploads.allowed_extensions',
          toLowerCase: true,
        ) ??
        existing.allowedExtensions;
    final directory =
        parseStringLike(merged['directory'], context: 'uploads.directory') ??
        existing.uploadDirectory;
    final filePermissions =
        parseIntLike(
          merged['file_permissions'],
          context: 'uploads.file_permissions',
        ) ??
        existing.filePermissions;

    return MultipartConfig(
      maxMemory: maxMemory,
      maxFileSize: maxFileSize,
      maxDiskUsage: maxDiskUsage,
      allowedExtensions: allowedExtensions,
      uploadDirectory: directory,
      filePermissions: filePermissions,
    );
  }

  bool _multipartEquals(MultipartConfig a, MultipartConfig b) {
    return a.maxMemory == b.maxMemory &&
        a.maxFileSize == b.maxFileSize &&
        a.maxDiskUsage == b.maxDiskUsage &&
        a.uploadDirectory == b.uploadDirectory &&
        a.filePermissions == b.filePermissions &&
        _setEquality.equals(
          a.allowedExtensions.map((e) => e.toLowerCase()).toSet(),
          b.allowedExtensions.map((e) => e.toLowerCase()).toSet(),
        );
  }
}
