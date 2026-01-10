import 'package:path/path.dart' as p;
import 'package:routed/src/storage/storage_manager.dart';

class StorageDefaults {
  StorageDefaults._(this.localDiskRoot, this.storageBase, this._path);

  factory StorageDefaults.fromManager(StorageManager manager) {
    String localRoot;
    try {
      localRoot = manager.disk().resolve('');
    } catch (_) {
      localRoot = 'storage/app';
    }
    return StorageDefaults.fromLocalRoot(localRoot);
  }

  factory StorageDefaults.fromLocalRoot(String root) {
    final pathContext = _contextFor(root);
    final normalized = pathContext.normalize(root);
    final base = _deriveStorageBase(normalized, pathContext);
    return StorageDefaults._(normalized, base, pathContext);
  }

  final String localDiskRoot;
  final String storageBase;
  final p.Context _path;

  String frameworkPath(String child) {
    return _path.normalize(_path.join(storageBase, 'framework', child));
  }

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
