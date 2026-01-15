import 'package:path/path.dart' as p;
import 'package:routed/src/contracts/contracts.dart' show Config;

/// {@template storage_base_resolution}
/// Resolves the base storage path used by storage helpers.
///
/// Precedence: `storage.base` → `app.root/storage` → `storage.root`
/// (or `storage.disks.local.root`) → `storage`.
/// Relative paths are resolved against `app.root` when present.
///
/// Example:
/// ```dart
/// final base = resolveStorageBasePath(config);
/// final cachePath = resolveFrameworkStoragePath(config, child: 'cache');
/// ```
/// {@endtemplate}

/// Resolves a `storage/framework/<child>` path.
/// {@macro storage_base_resolution}
String resolveFrameworkStoragePath(Config config, {required String child}) {
  final base = resolveStorageBasePath(config);
  return p.normalize(p.join(base, 'framework', child));
}

/// Normalizes `storage`-relative paths against the resolved storage base.
/// {@macro storage_base_resolution}
String normalizeStoragePath(Config config, String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return resolveStorageBasePath(config);
  }
  if (p.isAbsolute(trimmed)) {
    return p.normalize(trimmed);
  }
  final base = resolveStorageBasePath(config);
  if (trimmed == 'storage') {
    return p.normalize(base);
  }
  if (trimmed.startsWith('storage/')) {
    return p.normalize(p.join(base, trimmed.substring('storage/'.length)));
  }
  return p.normalize(p.join(base, trimmed));
}

/// {@macro storage_base_resolution}
String resolveStorageBasePath(Config config) {
  final configuredBase = _readPathValue(config, 'storage.base');
  if (configuredBase != null) {
    return _resolveAgainstAppRoot(config, configuredBase);
  }
  final appRoot = _readPathValue(config, 'app.root');
  if (appRoot != null) {
    return p.normalize(p.join(appRoot, 'storage'));
  }
  final configuredRoot =
      _readPathValue(config, 'storage.root') ??
      _readPathValue(config, 'storage.disks.local.root');
  if (configuredRoot != null) {
    return _deriveStorageBase(p.normalize(configuredRoot));
  }
  return p.normalize('storage');
}

String? _readPathValue(Config config, String key) {
  if (!config.has(key)) {
    return null;
  }
  final raw = config.get<Object?>(key);
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

String _resolveAgainstAppRoot(Config config, String path) {
  final normalized = p.normalize(path);
  if (p.isAbsolute(normalized)) {
    return normalized;
  }
  final appRoot = _readPathValue(config, 'app.root');
  if (appRoot != null) {
    return p.normalize(p.join(appRoot, normalized));
  }
  return normalized;
}

String _deriveStorageBase(String normalizedRoot) {
  final segments = p.split(normalizedRoot);
  if (segments.isEmpty) return 'storage';
  if (segments.last == 'app' && segments.length > 1) {
    return p.joinAll(segments.sublist(0, segments.length - 1));
  }
  final idx = segments.lastIndexOf('storage');
  if (idx != -1) {
    return p.joinAll(segments.sublist(0, idx + 1));
  }
  final dirname = p.dirname(normalizedRoot);
  if (dirname.isEmpty || dirname == '.') {
    return 'storage';
  }
  return dirname;
}
