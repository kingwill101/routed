import 'dart:convert';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:routed/src/contracts/cache/store.dart';
import 'package:routed/src/contracts/cache/lock_provider.dart';
import 'package:routed/src/cache/file_lock.dart';
import '../contracts/cache/lock.dart';

class FileStore implements Store, LockProvider {
  final Directory directory;
  final Directory? lockDirectory;
  final int? filePermission;
  final FileSystem fileSystem;

  FileStore(this.directory,
      [this.filePermission,
      this.lockDirectory,
      this.fileSystem = const LocalFileSystem()]);

  @override
  dynamic get(String key) {
    final payload = _getPayload(key);
    return payload['data'];
  }

  /// Get all keys in the store.
  ///
  /// This method reads all files in the directory and returns their keys.
  @override
  Future<List<String>> getAllKeys() async {
    final List<String> keys = [];
    final List<FileSystemEntity> entities = directory.listSync(recursive: true);
    final List<Future<void>> futures = [];

    for (final entity in entities) {
      if (entity is File) {
        futures.add(Future(() async {
          final key = entity.path
              .replaceFirst('${directory.path}/', '')
              .replaceAll('/', '');
          keys.add(key);
        }));
      }
    }

    await Future.wait(futures);
    return keys;
  }

  @override
  bool put(String key, dynamic value, int seconds) {
    final path = _path(key);
    _ensureCacheDirectoryExists(path);

    final expiresAt = _calculateExpiryTime(seconds);
    final file = fileSystem.file(path);
    file.writeAsStringSync(
        _serialize({'value': value, 'expiresAt': expiresAt}));
    if (file.existsSync()) {
      try {
        _ensurePermissionsAreCorrect(file);
      } catch (e) {
        file.deleteSync();
        return false;
      }
      return true;
    }
    return false;
  }

  @override
  bool forget(String key) {
    final file = fileSystem.file(_path(key));
    if (file.existsSync()) {
      file.deleteSync();
      return true;
    }
    return false;
  }

  @override
  bool flush() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
      directory.createSync();
      return true;
    }
    return false;
  }

  @override
  Future<Lock> lock(String name, [int seconds = 0, String? owner]) async {
    _ensureCacheDirectoryExists(lockDirectory?.path ?? directory.path);
    return FileLock(
      FileStore(directory, filePermission, lockDirectory),
      name,
      seconds,
      owner,
    );
  }

  @override
  Future<Lock> restoreLock(String name, String owner) async {
    return lock(name, 0, owner);
  }

  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) async {
    final raw = _getPayload(key);
    final currentValue = raw['data'] ?? 0;
    final newValue = (currentValue is int
            ? currentValue
            : int.parse(currentValue.toString())) +
        value;
    final expiresAt = raw['time'] ?? 0;
    put(key, newValue, expiresAt == 0 ? 0 : expiresAt);
    return newValue;
  }

  @override
  Future<dynamic> decrement(String key, [dynamic value = 1]) async {
    return increment(key, -value);
  }

  @override
  Future<bool> forever(String key, dynamic value) async {
    return put(key, value, 0);
  }

  @override
  String getPrefix() {
    return '';
  }

  @override
  Future<Map<String, dynamic>> many(List<String> keys) async {
    final Map<String, dynamic> results = {};
    for (var key in keys) {
      results[key] = await get(key);
    }
    return results;
  }

  @override
  Future<bool> putMany(Map<String, dynamic> values, int seconds) async {
    for (var entry in values.entries) {
      put(entry.key, entry.value, seconds);
    }
    return true;
  }

  Map<String, dynamic> _getPayload(String key) {
    final path = _path(key);
    final file = fileSystem.file(path);

    if (!file.existsSync()) {
      return _emptyPayload();
    }

    final contents = file.readAsStringSync();
    final data = _deserialize(contents);
    final expiresAt = data['expiresAt'];

    if (_isExpired(expiresAt)) {
      forget(key);
      return _emptyPayload();
    }

    return {'data': data['value'], 'time': _getRemainingTime(expiresAt)};
  }

  bool _isExpired(int expiresAt) {
    return expiresAt != 0 &&
        (DateTime.now().millisecondsSinceEpoch / 1000) >= expiresAt;
  }

  int _getRemainingTime(int expiresAt) {
    return expiresAt == 0
        ? 0
        : (expiresAt - DateTime.now().millisecondsSinceEpoch) ~/ 1000;
  }

  int _calculateExpiryTime(int seconds) {
    return seconds > 0
        ? DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch
        : 0;
  }

  Map<String, dynamic> _emptyPayload() {
    return {'data': null, 'time': null};
  }

  String _serialize(dynamic value) {
    return jsonEncode(value);
  }

  dynamic _deserialize(String value) {
    return jsonDecode(value);
  }

  String _path(String key) {
    final parts = key.split('');
    return '${directory.path}/${parts.join('/')}';
  }

  void _ensureCacheDirectoryExists(String path) {
    final dir = fileSystem.directory(path).parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      _ensurePermissionsAreCorrect(dir);
    }
  }

  void _ensurePermissionsAreCorrect(FileSystemEntity entity) {
    if (filePermission != null) {
      final stat = fileSystem.statSync(entity.path);

      final mode = stat.mode;
      if ((mode & 0x92) != 0x92) {
        throw FileSystemException('Entity is not writable', entity.path);
      }
    }
  }
}
