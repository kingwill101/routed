import 'package:file/file.dart' as file;
import 'package:file_sftp/file_sftp.dart'
    show SftpConfig, SftpFileSystem, SftpFilesystemAdapter;
import 'package:path/path.dart' as path;
import 'package:server_storage/src/storage_manager.dart';
import 'package:storage_fs/storage_fs.dart' show Filesystem;

/// A storage disk backed by an SSH File Transfer Protocol (SFTP) server.
///
/// The disk exposes the same `storage_fs` operations as local and S3 disks
/// through [storage], while [fileSystem] provides the `package:file` interface
/// used by static-file integrations. Both connections are established lazily;
/// constructing the disk does not contact the remote host.
///
/// Call [close] during application shutdown to release any SSH/SFTP sessions
/// opened by either interface.
final class SftpStorageDisk implements AsyncFilesystemStorageDisk {
  /// Creates an SFTP-backed storage disk from typed [config].
  ///
  /// Configuration requires a non-empty host and username, a valid TCP port,
  /// and either a password or at least one non-empty PEM private key. When a
  /// root is provided it must be an absolute POSIX path; all operations remain
  /// rooted beneath it.
  factory SftpStorageDisk({
    required SftpConfig config,
    String? diskName,
  }) {
    final validatedConfig = _validateConfig(config);
    final adapter = SftpFilesystemAdapter(validatedConfig);
    return SftpStorageDisk._(
      config: validatedConfig,
      fileSystem: SftpFileSystem(validatedConfig),
      adapter: adapter,
      storage: _BoundaryFilesystem(adapter, _resolvePath),
      diskName: diskName,
    );
  }

  const SftpStorageDisk._({
    required this.config,
    required this._fileSystem,
    required this._adapter,
    required this._storage,
    required this.diskName,
  });

  /// Validated connection and remote-filesystem configuration.
  ///
  /// This object includes authentication material. Do not log or serialize it.
  final SftpConfig config;

  /// Optional name associated with this disk by an integration.
  final String? diskName;

  final SftpFileSystem _fileSystem;
  final SftpFilesystemAdapter _adapter;
  final Filesystem _storage;

  /// The underlying SFTP `package:file` filesystem.
  @override
  file.FileSystem get fileSystem => _fileSystem;

  /// Unified Laravel-style storage operations over SFTP.
  @override
  Filesystem get storage => _storage;

  /// The underlying SFTP adapter for advanced access and connection control.
  SftpFilesystemAdapter get adapter => _adapter;

  /// Resolves a relative application path to a normalized SFTP path.
  ///
  /// The configured remote root is applied internally by [storage] and
  /// [fileSystem], so the returned value remains relative. Absolute paths and
  /// parent segments that escape the disk boundary are rejected.
  @override
  String resolve(String value) => _resolvePath(value);

  static String _resolvePath(String value) {
    if (value.isEmpty) {
      return '';
    }
    if (path.posix.isAbsolute(value)) {
      throw ArgumentError.value(value, 'path', 'SFTP paths must be relative.');
    }

    final normalized = path.posix.normalize(value);
    if (normalized == '.') {
      return '';
    }
    if (normalized == '..' || normalized.startsWith('../')) {
      throw ArgumentError.value(
        value,
        'path',
        'SFTP path escapes the configured storage root.',
      );
    }
    return normalized;
  }

  /// Closes SSH/SFTP sessions opened by this disk.
  ///
  /// It is safe to call this when the disk has not connected yet. A later
  /// operation may lazily establish a new connection.
  Future<void> close() async {
    await _adapter.disconnect();
    await _fileSystem.disconnect();
  }

  static SftpConfig _validateConfig(SftpConfig config) {
    final host = config.host.trim();
    final username = config.username.trim();
    if (host.isEmpty) {
      throw ArgumentError.value(config.host, 'config.host', 'Cannot be empty.');
    }
    if (username.isEmpty) {
      throw ArgumentError.value(
        config.username,
        'config.username',
        'Cannot be empty.',
      );
    }
    if (config.port < 1 || config.port > 65535) {
      throw ArgumentError.value(
        config.port,
        'config.port',
        'Must be between 1 and 65535.',
      );
    }

    final password = config.password;
    final privateKeys = config.privateKeyPems
        ?.where((key) => key.trim().isNotEmpty)
        .toList(growable: false);
    if ((password == null || password.isEmpty) &&
        (privateKeys == null || privateKeys.isEmpty)) {
      throw ArgumentError(
        'SFTP configuration requires a password or a PEM private key.',
      );
    }

    final configuredRoot = config.root?.trim();
    String? root;
    if (configuredRoot != null && configuredRoot.isNotEmpty) {
      if (!path.posix.isAbsolute(configuredRoot)) {
        throw ArgumentError.value(
          config.root,
          'config.root',
          'Must be an absolute POSIX path.',
        );
      }
      root = path.posix.normalize(configuredRoot);
    }

    return SftpConfig(
      host: host,
      port: config.port,
      username: username,
      password: password,
      privateKeyPems: privateKeys,
      privateKeyPassphrase: config.privateKeyPassphrase,
      root: root,
      throw_: config.throw_,
      readOnly: config.readOnly,
      directorySeparator: config.directorySeparator,
      timeout: config.timeout,
      connectTimeout: config.connectTimeout,
    );
  }
}

final class _BoundaryFilesystem implements Filesystem {
  const _BoundaryFilesystem(this._delegate, this._resolve);

  final Filesystem _delegate;
  final String Function(String path) _resolve;

  @override
  Future<bool> exists(String path) => _delegate.exists(_resolve(path));

  @override
  Future<bool> missing(String path) => _delegate.missing(_resolve(path));

  @override
  Future<String?> get(String path) => _delegate.get(_resolve(path));

  @override
  Stream<List<int>>? readStream(String path) {
    return _delegate.readStream(_resolve(path));
  }

  @override
  Future<bool> put(
    String path,
    dynamic contents, {
    Map<String, dynamic>? options,
  }) {
    return _delegate.put(_resolve(path), contents, options: options);
  }

  @override
  Future<bool> writeStream(
    String path,
    Stream<List<int>> resource, {
    Map<String, dynamic>? options,
  }) {
    return _delegate.writeStream(
      _resolve(path),
      resource,
      options: options,
    );
  }

  @override
  Future<String> getVisibility(String path) {
    return _delegate.getVisibility(_resolve(path));
  }

  @override
  Future<bool> setVisibility(String path, String visibility) {
    return _delegate.setVisibility(_resolve(path), visibility);
  }

  @override
  Future<bool> prepend(
    String path,
    String data, {
    String separator = '\n',
  }) {
    return _delegate.prepend(_resolve(path), data, separator: separator);
  }

  @override
  Future<bool> append(
    String path,
    String data, {
    String separator = '\n',
  }) {
    return _delegate.append(_resolve(path), data, separator: separator);
  }

  @override
  Future<bool> delete(dynamic paths) {
    if (paths is List) {
      return _delegate.delete(
        paths.map((value) => _resolve(value as String)).toList(growable: false),
      );
    }
    return _delegate.delete(_resolve(paths as String));
  }

  @override
  Future<bool> copy(String from, String to) {
    return _delegate.copy(_resolve(from), _resolve(to));
  }

  @override
  Future<bool> move(String from, String to) {
    return _delegate.move(_resolve(from), _resolve(to));
  }

  @override
  Future<int> size(String path) => _delegate.size(_resolve(path));

  @override
  Future<String?> checksum(String path, {String algorithm = 'md5'}) {
    return _delegate.checksum(_resolve(path), algorithm: algorithm);
  }

  @override
  Future<String?> mimeType(String path) {
    return _delegate.mimeType(_resolve(path));
  }

  @override
  Future<DateTime> lastModified(String path) {
    return _delegate.lastModified(_resolve(path));
  }

  @override
  Future<List<String>> files([
    String? directory,
    bool recursive = false,
  ]) {
    return _delegate.files(_resolve(directory ?? ''), recursive);
  }

  @override
  Future<List<String>> allFiles([String? directory]) {
    return _delegate.allFiles(_resolve(directory ?? ''));
  }

  @override
  Future<List<String>> directories([
    String? directory,
    bool recursive = false,
  ]) {
    return _delegate.directories(_resolve(directory ?? ''), recursive);
  }

  @override
  Future<List<String>> allDirectories([String? directory]) {
    return _delegate.allDirectories(_resolve(directory ?? ''));
  }

  @override
  Future<bool> makeDirectory(String path) {
    return _delegate.makeDirectory(_resolve(path));
  }

  @override
  Future<bool> deleteDirectory(String directory) {
    return _delegate.deleteDirectory(_resolve(directory));
  }
}
