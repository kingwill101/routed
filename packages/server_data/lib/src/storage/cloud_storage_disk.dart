import 'package:file/file.dart' as file;
import 'package:storage_fs/storage_fs.dart';

import 'storage_manager.dart';

/// Storage disk backed by an S3-compatible cloud filesystem.
class CloudStorageDisk implements StorageDisk {
  CloudStorageDisk({required CloudAdapter adapter, this.diskName})
    : _adapter = adapter;

  final CloudAdapter _adapter;

  /// Name associated with this disk inside the manager.
  final String? diskName;

  /// Exposes the underlying cloud adapter for advanced integrations.
  CloudAdapter get adapter => _adapter;

  @override
  file.FileSystem get fileSystem => _adapter.fileSystem;

  @override
  String resolve(String path) {
    final normalized = adapter.fileSystem.path.normalize(path);
    if (normalized.isEmpty || normalized == '.') {
      return '';
    }
    return normalized.startsWith('/') ? normalized.substring(1) : normalized;
  }
}
