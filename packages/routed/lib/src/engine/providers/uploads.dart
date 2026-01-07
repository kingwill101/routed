import 'dart:async';

import 'package:collection/collection.dart';
import 'package:routed/src/container/container.dart';
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/config/specs/uploads.dart';
import 'package:routed/src/engine/config.dart';
import 'package:routed/src/engine/engine.dart';
import 'package:routed/src/provider/provider.dart';

/// Configures multipart upload defaults.
class UploadsServiceProvider extends ServiceProvider
    with ProvidesDefaultConfig {
  Engine? _engine;

  static const _setEquality = SetEquality<String>();
  static const UploadsConfigSpec spec = UploadsConfigSpec();

  @override
  ConfigDefaults get defaultConfig =>
      ConfigDefaults(docs: spec.docs(), values: spec.defaultsWithRoot());

  @override
  void register(Container container) {
    if (!container.has<Config>() || !container.has<EngineConfig>()) {
      return;
    }
    final appConfig = container.get<Config>();
    final engineConfig = container.get<EngineConfig>();
    final resolved = spec.resolve(
      appConfig,
      context: UploadsConfigContext(
        config: appConfig,
        engineConfig: engineConfig,
      ),
    );

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
    final resolved = spec.resolve(
      config,
      context: UploadsConfigContext(
        config: config,
        engineConfig: current,
      ),
    );
    if (_multipartEquals(current.multipart, resolved)) {
      return;
    }
    engine.updateConfig(current.copyWith(multipart: resolved));
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
