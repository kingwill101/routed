import 'package:file/file.dart' as file;
import 'package:server_storage/src/storage_manager.dart';
import 'package:storage_fs/storage_fs.dart';

/// Resolves object keys through an S3-compatible cloud filesystem.
///
/// The adapter owns the cloud connection and filesystem implementation. This
/// wrapper gives it the [StorageDisk] contract so it can be selected by a
/// [StorageManager]. It does not create buckets, upload objects, or close the
/// adapter when the manager is cleared.
class CloudStorageDisk implements StorageDisk {
  /// Creates a disk backed by [adapter].
  ///
  /// [diskName] is descriptive metadata for integrations; it does not alter
  /// key resolution or register the disk with a manager.
  CloudStorageDisk({required CloudAdapter adapter, this.diskName})
    : _adapter = adapter;

  final CloudAdapter _adapter;

  /// Optional name associated with this disk by an integration.
  final String? diskName;

  /// The underlying cloud adapter for storage operations and advanced setup.
  CloudAdapter get adapter => _adapter;

  @override
  file.FileSystem get fileSystem => _adapter.fileSystem;

  @override
  String resolve(String path) {
    // Cloud paths are object keys rather than local filesystem paths.
    final normalized = adapter.fileSystem.path.normalize(path);
    if (normalized.isEmpty || normalized == '.') {
      return '';
    }
    return normalized.startsWith('/') ? normalized.substring(1) : normalized;
  }
}
