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

    // Strict validation for invalid types
    final maxMemoryRaw = merged['max_memory'];
    final maxMemory = maxMemoryRaw == null
        ? existing.maxMemory
        : maxMemoryRaw is int
        ? maxMemoryRaw
        : throw ProviderConfigException(
            'uploads.max_memory must be an integer',
          );

    final maxFileSizeRaw = merged['max_file_size'];
    final maxFileSize = maxFileSizeRaw == null
        ? existing.maxFileSize
        : maxFileSizeRaw is int
        ? maxFileSizeRaw
        : throw ProviderConfigException(
            'uploads.max_file_size must be an integer',
          );

    final maxDiskUsageRaw = merged['max_disk_usage'];
    final maxDiskUsage = maxDiskUsageRaw == null
        ? existing.maxDiskUsage
        : maxDiskUsageRaw is int
        ? maxDiskUsageRaw
        : throw ProviderConfigException(
            'uploads.max_disk_usage must be an integer',
          );

    final allowedExtensionsRaw = merged['allowed_extensions'];
    final allowedExtensions = allowedExtensionsRaw == null
        ? existing.allowedExtensions
        : allowedExtensionsRaw is List
        ? _validateStringList(
            allowedExtensionsRaw,
            'uploads.allowed_extensions',
          ).toSet()
        : throw ProviderConfigException(
            'uploads.allowed_extensions must be a list',
          );

    final directoryRaw = merged['directory'];
    final directory = directoryRaw == null
        ? existing.uploadDirectory
        : directoryRaw is String
        ? directoryRaw
        : throw ProviderConfigException('uploads.directory must be a string');

    final filePermissionsRaw = merged['file_permissions'];
    final filePermissions = filePermissionsRaw == null
        ? existing.filePermissions
        : filePermissionsRaw is int
        ? filePermissionsRaw
        : throw ProviderConfigException(
            'uploads.file_permissions must be an integer',
          );

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

  List<String> _validateStringList(List<dynamic> list, String context) {
    final result = <String>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! String) {
        throw ProviderConfigException('$context[$i] must be a string');
      }
      result.add(item);
    }
    return result;
  }
}
