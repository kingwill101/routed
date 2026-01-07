import 'package:path/path.dart' as p;
import 'package:routed/src/storage/storage_manager.dart';

class StorageDefaults {
  StorageDefaults._(this.localDiskRoot, this.storageBase);

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
    final normalized = p.normalize(root.replaceAll('\\', '/'));
    final base = _deriveStorageBase(normalized);
    return StorageDefaults._(normalized, base);
  }

  final String localDiskRoot;
  final String storageBase;

  String frameworkPath(String child) {
    return p.normalize(p.join(storageBase, 'framework', child));
  }

  String resolve(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return storageBase;
    }
    if (p.isAbsolute(trimmed)) {
      return p.normalize(trimmed);
    }
    if (trimmed == 'storage') {
      return storageBase;
    }
    if (trimmed.startsWith('storage/')) {
      return p.normalize(
        p.join(storageBase, trimmed.substring('storage/'.length)),
      );
    }
    return p.normalize(p.join(storageBase, trimmed));
  }
}

String _deriveStorageBase(String normalizedRoot) {
  final segments = p.posix.split(normalizedRoot);
  if (segments.isEmpty) return 'storage';
  if (segments.last == 'app' && segments.length > 1) {
    final baseSegments = segments.sublist(0, segments.length - 1);
    if (baseSegments.isEmpty) return 'storage';
    return p.posix.joinAll(baseSegments);
  }
  final idx = segments.lastIndexOf('storage');
  if (idx != -1) {
    return p.posix.joinAll(segments.sublist(0, idx + 1));
  }
  // fallback to directory containing root
  final dirname = p.dirname(normalizedRoot);
  if (dirname.isEmpty || dirname == '.') {
    return 'storage';
  }
  return dirname;
}
