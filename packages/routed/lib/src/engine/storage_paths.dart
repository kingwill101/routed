import 'package:path/path.dart' as p;
import 'package:routed/src/contracts/contracts.dart' show Config;

String resolveFrameworkStoragePath(Config config, {required String child}) {
  final base = _storageRoot(config);
  return p.normalize(p.join(base, 'framework', child));
}

String normalizeStoragePath(Config config, String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return _storageRoot(config);
  }
  if (p.isAbsolute(trimmed)) {
    return p.normalize(trimmed);
  }
  if (trimmed.startsWith('storage')) {
    return p.normalize(trimmed);
  }
  final base = _storageRoot(config);
  return p.normalize(p.join(base, trimmed));
}

String _storageRoot(Config config) {
  final raw = config.has('storage.disks.local.root')
      ? config.get('storage.disks.local.root')
      : null;
  String root;
  if (raw is String && raw.trim().isNotEmpty) {
    root = raw.trim();
  } else {
    root = 'storage/app';
  }
  root = p.normalize(root);
  if (p.basename(root) == 'app') {
    final parent = p.dirname(root);
    if (parent.isEmpty || parent == '.') {
      return 'storage';
    }
    return parent;
  }
  return root;
}
