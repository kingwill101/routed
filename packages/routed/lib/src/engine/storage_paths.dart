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
  final pathContext = _pathContextForConfig(config);
  final base = resolveStorageBasePath(config, pathContext: pathContext);
  return pathContext.normalize(pathContext.join(base, 'framework', child));
}

/// Normalizes `storage`-relative paths against the resolved storage base.
/// {@macro storage_base_resolution}
String normalizeStoragePath(Config config, String path) {
  final pathContext = _pathContextForConfig(config);
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return resolveStorageBasePath(config, pathContext: pathContext);
  }
  if (pathContext.isAbsolute(trimmed)) {
    return pathContext.normalize(trimmed);
  }
  final base = resolveStorageBasePath(config, pathContext: pathContext);
  if (trimmed == 'storage') {
    return pathContext.normalize(base);
  }
  if (trimmed.startsWith('storage/')) {
    return pathContext.normalize(
      pathContext.join(base, trimmed.substring('storage/'.length)),
    );
  }
  return pathContext.normalize(pathContext.join(base, trimmed));
}

/// {@macro storage_base_resolution}
String resolveStorageBasePath(Config config, {p.Context? pathContext}) {
  final context = pathContext ?? _pathContextForConfig(config);
  final configuredBase = _readPathValue(config, 'storage.base');
  if (configuredBase != null) {
    return _resolveAgainstAppRoot(config, configuredBase, context);
  }
  final appRoot = _readPathValue(config, 'app.root');
  if (appRoot != null) {
    return context.normalize(context.join(appRoot, 'storage'));
  }
  final configuredRoot =
      _readPathValue(config, 'storage.root') ??
      _readPathValue(config, 'storage.disks.local.root');
  if (configuredRoot != null) {
    return _deriveStorageBase(context.normalize(configuredRoot), context);
  }
  return context.normalize('storage');
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

String _resolveAgainstAppRoot(
  Config config,
  String path,
  p.Context pathContext,
) {
  final normalized = pathContext.normalize(path);
  if (pathContext.isAbsolute(normalized)) {
    return normalized;
  }
  final appRoot = _readPathValue(config, 'app.root');
  if (appRoot != null) {
    return pathContext.normalize(pathContext.join(appRoot, normalized));
  }
  return normalized;
}

String _deriveStorageBase(String normalizedRoot, p.Context pathContext) {
  final segments = pathContext.split(normalizedRoot);
  if (segments.isEmpty) return 'storage';
  if (segments.last == 'app' && segments.length > 1) {
    return pathContext.joinAll(segments.sublist(0, segments.length - 1));
  }
  final idx = segments.lastIndexOf('storage');
  if (idx != -1) {
    return pathContext.joinAll(segments.sublist(0, idx + 1));
  }
  final dirname = pathContext.dirname(normalizedRoot);
  if (dirname.isEmpty || dirname == '.') {
    return 'storage';
  }
  return dirname;
}

p.Context _pathContextForConfig(Config config) {
  final candidates = <String?>[
    _readPathValue(config, 'storage.base'),
    _readPathValue(config, 'app.root'),
    _readPathValue(config, 'storage.root'),
    _readPathValue(config, 'storage.disks.local.root'),
  ];
  for (final candidate in candidates) {
    if (candidate != null && candidate.trim().isNotEmpty) {
      return _contextFor(candidate);
    }
  }
  return p.Context(style: p.Style.posix);
}

p.Context _contextFor(String root) {
  final hasBackslash = root.contains('\\');
  final hasDrive = RegExp(r'^[a-zA-Z]:').hasMatch(root);
  if (hasBackslash || hasDrive) {
    return p.Context(style: p.Style.windows);
  }
  return p.Context(style: p.Style.posix);
}
