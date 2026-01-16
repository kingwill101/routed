import 'package:path/path.dart' as p;
import 'package:routed/src/contracts/contracts.dart' show Config;
import 'package:routed/src/engine/storage_paths.dart';
import 'package:routed/src/storage/storage_manager.dart';

/// {@template storage_defaults}
/// Derives normalized defaults for storage helpers.
///
/// `storageBase` prefers `storage.base` (or `app.root/storage`), while
/// `localDiskRoot` reflects the default disk root when available.
///
/// Example:
/// ```dart
/// final defaults = StorageDefaults.fromConfig(config, manager);
/// final cachePath = defaults.frameworkPath('cache');
/// ```
/// {@endtemplate}

/// {@macro storage_defaults}
class StorageDefaults {
  StorageDefaults._(this.localDiskRoot, this.storageBase, this._path);

  /// Builds defaults from the storage manager, optionally overriding the base.
  factory StorageDefaults.fromManager(
    StorageManager manager, {
    String? storageBase,
  }) {
    String localRoot;
    try {
      localRoot = manager.disk().resolve('');
    } catch (_) {
      localRoot = 'storage/app';
    }
    return StorageDefaults.fromRoots(localRoot, storageBase: storageBase);
  }

  /// {@macro storage_defaults}
  factory StorageDefaults.fromConfig(Config config, StorageManager manager) {
    final base = resolveStorageBasePath(config);
    return StorageDefaults.fromManager(manager, storageBase: base);
  }

  /// Builds defaults directly from a local disk root.
  factory StorageDefaults.fromLocalRoot(String root) {
    return StorageDefaults.fromRoots(root);
  }

  /// {@macro storage_defaults}
  factory StorageDefaults.fromRoots(String localRoot, {String? storageBase}) {
    final baseValue = storageBase?.trim();
    final contextSeed = (baseValue != null && baseValue.isNotEmpty)
        ? baseValue
        : localRoot;
    final pathContext = _contextFor(contextSeed);
    final normalizedLocal = pathContext.normalize(localRoot);
    final resolvedBase = (baseValue != null && baseValue.isNotEmpty)
        ? pathContext.normalize(baseValue)
        : _deriveStorageBase(normalizedLocal, pathContext);
    return StorageDefaults._(normalizedLocal, resolvedBase, pathContext);
  }

  final String localDiskRoot;
  final String storageBase;
  final p.Context _path;

  /// Resolves a `storage/framework/<child>` path from the base.
  String frameworkPath(String child) {
    return _path.normalize(_path.join(storageBase, 'framework', child));
  }

  /// Normalizes a storage-relative path against the base.
  String resolve(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return storageBase;
    }
    if (_path.isAbsolute(trimmed)) {
      return _path.normalize(trimmed);
    }
    final normalizedInput = trimmed.replaceAll('\\', '/');
    if (normalizedInput == 'storage') {
      return storageBase;
    }
    if (normalizedInput.startsWith('storage/')) {
      return _path.normalize(
        _path.join(storageBase, normalizedInput.substring('storage/'.length)),
      );
    }
    return _path.normalize(_path.join(storageBase, normalizedInput));
  }
}

p.Context _contextFor(String root) {
  final hasBackslash = root.contains('\\');
  final hasDrive = RegExp(r'^[a-zA-Z]:').hasMatch(root);
  if (hasBackslash || hasDrive) {
    return p.Context(style: p.Style.windows);
  }
  return p.Context(style: p.Style.posix);
}

String _deriveStorageBase(String normalizedRoot, p.Context pathContext) {
  final segments = pathContext.split(normalizedRoot);
  if (segments.isEmpty) return 'storage';
  if (segments.last == 'app' && segments.length > 1) {
    final baseSegments = segments.sublist(0, segments.length - 1);
    if (baseSegments.isEmpty) return 'storage';
    return pathContext.joinAll(baseSegments);
  }
  final idx = segments.lastIndexOf('storage');
  if (idx != -1) {
    return pathContext.joinAll(segments.sublist(0, idx + 1));
  }
  // fallback to directory containing root
  final dirname = pathContext.dirname(normalizedRoot);
  if (dirname.isEmpty || dirname == '.') {
    return 'storage';
  }
  return dirname;
}
