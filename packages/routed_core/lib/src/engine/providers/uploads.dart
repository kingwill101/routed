import 'dart:async';

import 'package:collection/collection.dart';
import 'package:routed_core/src/container/container.dart';
import 'package:routed_core/src/engine/config.dart';
import 'package:routed_core/src/engine/engine.dart';
import 'package:routed_core/src/provider/provider.dart';
import 'package:routed_core/src/provider/typed_provider.dart';

/// Configures multipart upload defaults.
class UploadsServiceProvider extends ServiceProvider
    with ProvidesTypedConfiguration<MultipartConfig> {
  /// Creates an uploads provider with optional [configuration].
  UploadsServiceProvider([MultipartConfig? configuration])
    : configuration = configuration ?? MultipartConfig();

  @override
  final MultipartConfig configuration;

  Engine? _engine;

  static const _setEquality = SetEquality<String>();

  @override
  void register(Container container) {}

  @override
  Future<void> boot(Container container) async {
    if (container.has<Engine>()) {
      _engine = await container.make<Engine>();
      _applyMultipartConfig(_engine!, configuration);
    }
  }

  void _applyMultipartConfig(Engine engine, MultipartConfig resolved) {
    final current = engine.config;
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
