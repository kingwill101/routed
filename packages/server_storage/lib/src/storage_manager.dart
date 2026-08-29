import 'package:file/file.dart' as file;
import 'package:file/local.dart' as local;
import 'package:storage_fs/storage_fs.dart' show CloudAdapter, Filesystem;

/// Resolves application paths against a configured storage disk.
///
/// Implementations decide how a path is represented. A local disk returns an
/// absolute filesystem path, while a cloud disk normally returns an object
/// key. Implementations should reject paths that violate their own storage
/// boundary.
abstract class StorageDisk {
  /// The filesystem associated with this disk.
  ///
  /// For a cloud disk this is the adapter's cloud filesystem. The value is
  /// exposed so framework adapters can perform storage operations without
  /// depending on a concrete disk implementation.
  file.FileSystem get fileSystem;

  /// Resolves the application-relative [path] for this disk.
  ///
  /// The returned form is implementation-specific. Callers should pass
  /// relative, untrusted paths to this method instead of constructing paths
  /// by joining a disk root themselves.
  String resolve(String path);
}

/// A storage disk that exposes Laravel-style filesystem operations.
///
/// Built-in local and cloud disks implement this contract. Custom disks can
/// implement only [StorageDisk] when they need path resolution, or implement
/// this interface as well so [StorageManager.storage] can return their
/// operational filesystem.
abstract interface class FilesystemStorageDisk implements StorageDisk {
  /// Unified asynchronous file operations for this disk.
  Filesystem get storage;
}

/// Marks a disk whose `package:file` implementation requires asynchronous I/O.
///
/// Framework static-file adapters use [storage] for these disks rather than
/// invoking synchronous methods through [StorageDisk.fileSystem]. Remote
/// filesystems such as SFTP and cloud object stores implement this contract.
abstract interface class AsyncFilesystemStorageDisk
    implements FilesystemStorageDisk {}

/// Registers and selects named storage disks for an application.
///
/// A manager is an in-memory registry. Constructing it does not create a
/// directory, connect to a cloud service, or register a `local` disk. The
/// default name starts as `local`, so register that disk before resolving a
/// path unless an application selects another name.
class StorageManager {
  /// Creates a manager with [defaultFileSystem] available to disk factories.
  ///
  /// The manager does not create disks from this filesystem automatically.
  /// Supplying an in-memory filesystem is useful when constructing disks in
  /// tests; production code normally uses the default local filesystem.
  StorageManager({file.FileSystem? defaultFileSystem})
    : _defaultFileSystem = defaultFileSystem ?? const local.LocalFileSystem();

  final Map<String, Object> _disks = {};
  String _defaultDisk = 'local';
  final file.FileSystem _defaultFileSystem;

  /// Removes every registered disk.
  ///
  /// This does not reset [defaultDisk] or delete any files. Register a disk
  /// under the selected default name before using [disk] or [resolve] again.
  void clear() {
    _disks.clear();
  }

  /// Sets the name used when a disk is not selected explicitly.
  ///
  /// The name is not required to be registered at this point. A later call to
  /// [disk] or [resolve] throws [StateError] until a matching disk is added.
  ///
  /// Throws [ArgumentError] when [name] is empty.
  void setDefault(String name) {
    if (name.isEmpty) {
      throw ArgumentError('Default disk name cannot be empty.');
    }
    _defaultDisk = name;
  }

  /// Registers [disk] under [name], replacing an existing registration.
  ///
  /// Registration changes only this in-memory registry; it does not create or
  /// remove files and does not close the replaced disk.
  ///
  /// Throws [ArgumentError] when [name] is empty.
  void registerDisk(String name, StorageDisk disk) {
    if (name.isEmpty) {
      throw ArgumentError('Disk name cannot be empty.');
    }
    _disks[name] = disk;
  }

  /// Registers storage operations that do not expose `package:file` paths.
  ///
  /// This is intended for host-native object stores, such as a Cloudflare R2
  /// Worker binding, where [Filesystem] operations are available but a
  /// synchronous [file.FileSystem] cannot be implemented safely. The
  /// filesystem can be selected through [storage] and [drive]. Calling [disk]
  /// or [resolve] for this registration throws [UnsupportedError].
  ///
  /// Registering a filesystem replaces any disk with the same [name].
  /// Throws [ArgumentError] when [name] is empty.
  void registerFilesystem(String name, Filesystem filesystem) {
    if (name.isEmpty) {
      throw ArgumentError('Disk name cannot be empty.');
    }
    _disks[name] = filesystem;
  }

  /// Returns whether a disk named [name] is registered.
  bool hasDisk(String name) => _disks.containsKey(name);

  /// A snapshot of the registered disk names in insertion order.
  List<String> get diskNames => _disks.keys.toList(growable: false);

  /// Whether the selected registration supports `package:file` path access.
  ///
  /// Host-native filesystems registered with [registerFilesystem] return
  /// `false`; disks registered with [registerDisk] return `true`. The default
  /// registration is selected when [name] is omitted or empty.
  ///
  /// Throws [StateError] when the selected name is not registered.
  bool supportsPathResolution([String? name]) {
    final key = _selectedName(name);
    final selected = _disks[key];
    if (selected == null) {
      throw StateError('Storage disk "$key" is not configured.');
    }
    return selected is StorageDisk;
  }

  /// Whether the selected registration exposes asynchronous filesystem APIs.
  ///
  /// This is true for a [Filesystem] registered directly and for a disk that
  /// implements [FilesystemStorageDisk]. It is false for path-only custom
  /// disks. The default registration is selected when [name] is omitted.
  ///
  /// Throws [StateError] when the selected name is not registered.
  bool supportsFilesystemOperations([String? name]) {
    final key = _selectedName(name);
    final selected = _disks[key];
    if (selected == null) {
      throw StateError('Storage disk "$key" is not configured.');
    }
    return selected is Filesystem || selected is FilesystemStorageDisk;
  }

  /// Resolves [path] against [disk], or against [defaultDisk] when omitted.
  ///
  /// The selected disk controls normalization and path-safety behavior. This
  /// method does not read from or write to the filesystem.
  ///
  /// Throws [StateError] when the selected disk is not registered.
  String resolve(String path, {String? disk}) {
    return this.disk(disk).resolve(path);
  }

  /// Returns the disk named [name], or the default disk when omitted or empty.
  ///
  /// Throws [StateError] when the selected disk is not registered.
  StorageDisk disk([String? name]) {
    final key = (name == null || name.isEmpty) ? _defaultDisk : name;
    final registration = _disks[key];
    if (registration == null) {
      throw StateError('Storage disk "$key" is not configured.');
    }
    if (registration is StorageDisk) {
      return registration;
    }
    throw UnsupportedError(
      'Storage disk "$key" exposes filesystem operations but not '
      '`package:file` paths.',
    );
  }

  /// Returns Laravel-style filesystem operations for the selected disk.
  ///
  /// The selected disk is the default when [name] is omitted or empty. Local
  /// and S3 disks support this API, so application code can use the same
  /// `put`, `get`, `exists`, `delete`, and streaming methods for either.
  ///
  /// Throws [UnsupportedError] when a custom disk implements path resolution
  /// only and does not implement [FilesystemStorageDisk].
  Filesystem storage([String? name]) {
    final key = _selectedName(name);
    final selected = _disks[key];
    if (selected == null) {
      throw StateError('Storage disk "$key" is not configured.');
    }
    if (selected is Filesystem) {
      return selected;
    }
    if (selected case FilesystemStorageDisk(:final storage)) {
      return storage;
    }
    throw UnsupportedError(
      'Storage disk "${_selectedName(name)}" does not expose filesystem '
      'operations.',
    );
  }

  /// Alias for [storage], matching `storage_fs` drive terminology.
  Filesystem drive([String? name]) => storage(name);

  /// Returns cloud-specific operations for the selected disk.
  ///
  /// Use this for cloud-specific and temporary download/upload URLs.
  /// Throws [UnsupportedError] when the selected disk is not cloud-backed.
  CloudAdapter cloud([String? name]) {
    final filesystem = storage(name);
    if (filesystem is CloudAdapter) {
      return filesystem;
    }
    throw UnsupportedError(
      'Storage disk "${_selectedName(name)}" is not cloud-backed.',
    );
  }

  /// The name selected for implicit disk lookups.
  String get defaultDisk => _defaultDisk;

  /// The filesystem supplied to code that creates disks from this manager.
  ///
  /// Reading this property does not create a disk or alter the registry.
  file.FileSystem get defaultFileSystem => _defaultFileSystem;

  String _selectedName(String? name) {
    return name == null || name.isEmpty ? _defaultDisk : name;
  }
}
