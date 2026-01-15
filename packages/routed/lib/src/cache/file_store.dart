import 'dart:convert';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:routed/src/cache/file_lock.dart';
import 'package:routed/src/contracts/cache/lock_provider.dart';
import 'package:routed/src/contracts/cache/store.dart';
import 'package:routed/src/crypto/crypto.dart';

import '../contracts/cache/lock.dart';

/// Implements the [Store] and [LockProvider] contracts using files for storage.
///
/// This class provides a file-based cache store where each cache item
/// is stored as a separate file. It supports setting file permissions
/// and using a separate directory for lock files.
class FileStore implements Store, LockProvider {
  /// The main directory used for storing cache items.
  final Directory directory;

  /// An optional directory used for storing lock files.
  /// If null, the main [directory] is used.
  final Directory? lockDirectory;

  /// Optional file permissions to set on created cache files.
  final int? filePermission;

  /// The file system to use for file operations.
  final FileSystem fileSystem;

  /// Creates a [FileStore] instance.
  ///
  /// The [directory] parameter is required and specifies the main directory
  /// for storing cache items.
  ///
  /// The [filePermission] parameter is optional and specifies the file
  /// permissions to set on created cache files.
  ///
  /// The [lockDirectory] parameter is optional and specifies a separate
  /// directory for storing lock files. If null, the main [directory] is used.
  ///
  /// The [fileSystem] parameter is optional and specifies the file system
  /// to use for file operations. Defaults to a [LocalFileSystem].
  FileStore(
    this.directory, [
    this.filePermission,
    this.lockDirectory,
    this.fileSystem = const LocalFileSystem(),
  ]);

  /// Retrieves an item from the cache.
  ///
  /// Returns the cached value if found and not expired; otherwise, returns null.
  @override
  dynamic get(String key) {
    final payload = _getPayload(key);
    return payload['data'];
  }

  /// Retrieves all keys from the store.
  ///
  /// This method reads all cache files and extracts the original keys
  /// stored within each file's metadata.
  @override
  Future<List<String>> getAllKeys() async {
    final List<String> keys = [];
    if (!directory.existsSync()) {
      return keys;
    }
    final List<FileSystemEntity> entities = await directory
        .list(recursive: true)
        .toList();

    for (final entity in entities) {
      if (entity is File) {
        try {
          final contents = await entity.readAsString();
          final data = _deserialize(contents);
          final key = data['key'];
          if (key is String && key.isNotEmpty) {
            keys.add(key);
          }
        } catch (_) {
          // Skip files that can't be read or parsed
        }
      }
    }

    return keys;
  }

  /// Stores an item in the cache with a specified time-to-live (TTL).
  ///
  /// Returns true if the item was successfully stored.
  @override
  bool put(String key, dynamic value, int seconds) {
    final path = _path(key);
    _ensureCacheDirectoryExists(path);

    final expiresAt = _calculateExpiryTime(seconds);
    final file = fileSystem.file(path);
    file.writeAsStringSync(
      _serialize({'key': key, 'value': value, 'expiresAt': expiresAt}),
    );
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

  /// Removes an item from the cache.
  ///
  /// Returns true if the item was successfully removed.
  @override
  bool forget(String key) {
    final file = fileSystem.file(_path(key));
    if (file.existsSync()) {
      file.deleteSync();
      return true;
    }
    return false;
  }

  /// Clears all items from the cache.
  ///
  /// Returns true if the cache was successfully cleared.
  @override
  bool flush() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
      directory.createSync();
      return true;
    }
    return false;
  }

  /// Creates a lock for synchronization.
  ///
  /// Returns a [FileLock] instance.
  @override
  Future<Lock> lock(String name, [int seconds = 0, String? owner]) async {
    final targetDirectory = lockDirectory ?? directory;
    _ensureCacheDirectoryExists(targetDirectory.path);
    return FileLock(
      FileStore(targetDirectory, filePermission, lockDirectory, fileSystem),
      name,
      seconds,
      owner,
    );
  }

  /// Restores an existing lock.
  ///
  /// Returns a [Lock] instance.
  @override
  Future<Lock> restoreLock(String name, String owner) async {
    return lock(name, 0, owner);
  }

  /// Increments the value of an item in the cache by a given amount.
  ///
  /// Returns the new value.
  @override
  Future<dynamic> increment(String key, [dynamic value = 1]) async {
    final raw = _getPayload(key);
    final currentValue = raw['data'] ?? 0;
    final num numValue = (value is num) ? value : 1;
    final newValue =
        (currentValue is int
            ? currentValue
            : int.parse(currentValue.toString())) +
        numValue;
    final expiresAt = raw['time'] ?? 0;
    final int expTime = (expiresAt is int) ? expiresAt : 0;
    put(key, newValue, expTime == 0 ? 0 : expTime);
    return newValue;
  }

  /// Decrements the value of an item in the cache by a given amount.
  ///
  /// Returns the new value.
  @override
  Future<dynamic> decrement(String key, [dynamic value = 1]) async {
    final num numValue = (value is num) ? value : 1;
    return increment(key, -numValue);
  }

  /// Stores an item in the cache permanently, without expiration.
  ///
  /// Returns true if the item was successfully stored.
  @override
  Future<bool> forever(String key, dynamic value) async {
    return put(key, value, 0);
  }

  /// Gets the prefix used for cache keys.
  ///
  /// Always returns an empty string.
  @override
  String getPrefix() {
    return '';
  }

  /// Retrieves multiple items from the cache by their keys.
  ///
  /// Returns a map of key-value pairs.
  @override
  Future<Map<String, dynamic>> many(List<String> keys) async {
    final Map<String, dynamic> results = {};
    for (var key in keys) {
      results[key] = await get(key);
    }
    return results;
  }

  /// Stores multiple items in the cache with a specified time-to-live (TTL).
  ///
  /// Returns true if all items were successfully stored.
  @override
  Future<bool> putMany(Map<String, dynamic> values, int seconds) async {
    for (var entry in values.entries) {
      put(entry.key, entry.value, seconds);
    }
    return true;
  }

  /// Retrieves the payload for a given cache key.
  ///
  /// Returns a map containing the data and expiration time, or an empty
  /// payload if the key does not exist or is expired.
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

  /// Checks if a cache item has expired.
  ///
  /// Returns true if the item has expired; otherwise, returns false.
  bool _isExpired(dynamic expiresAt) {
    final int expTime = expiresAt is int ? expiresAt : 0;
    return expTime != 0 &&
        (DateTime.now().millisecondsSinceEpoch / 1000) >= expTime;
  }

  /// Gets the remaining time until a cache item expires.
  ///
  /// Returns the remaining time in seconds, or 0 if the item does not expire.
  int _getRemainingTime(dynamic expiresAt) {
    final int expTime = expiresAt is int ? expiresAt : 0;
    return expTime == 0
        ? 0
        : (expTime - DateTime.now().millisecondsSinceEpoch) ~/ 1000;
  }

  /// Calculates the expiration timestamp based on the specified TTL.
  ///
  /// Returns the expiration timestamp in milliseconds since epoch.
  int _calculateExpiryTime(int seconds) {
    return seconds > 0
        ? DateTime.now().add(Duration(seconds: seconds)).millisecondsSinceEpoch
        : 0;
  }

  /// Creates an empty payload for non-existent or expired cache items.
  ///
  /// Returns a map with null data and time.
  Map<String, dynamic> _emptyPayload() {
    return {'data': null, 'time': null};
  }

  /// Serializes a value to a JSON string.
  ///
  /// Returns the serialized JSON string.
  String _serialize(dynamic value) {
    return jsonEncode(value);
  }

  /// Deserializes a JSON string to its original value.
  ///
  /// Returns the deserialized value.
  dynamic _deserialize(String value) {
    return jsonDecode(value);
  }

  /// Generates the file path for a given cache key.
  ///
  /// Uses SHA-1 hash of the key to create a balanced directory structure
  /// with 2 levels of 2-character directories, followed by the full hash
  /// as the filename. This prevents creating excessively deep directory
  /// trees while still distributing cache files evenly.
  ///
  /// Returns the file path.
  String _path(String key) {
    final hash = hexFromBytes(sha1Digest(utf8.encode(key)));
    // Create 2 levels of 2-character directories for balanced distribution
    final dir1 = hash.substring(0, 2);
    final dir2 = hash.substring(2, 4);
    final pathContext = directory.fileSystem.path;
    return pathContext.join(directory.path, dir1, dir2, hash);
  }

  /// Ensures that the cache directory exists.
  ///
  /// If the directory does not exist, it creates it and sets the file permissions.
  void _ensureCacheDirectoryExists(String path) {
    final dir = fileSystem.directory(path).parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      _ensurePermissionsAreCorrect(dir);
    }
  }

  /// Ensures that the file permissions are correct for a given entity.
  ///
  /// Throws a [FileSystemException] if the permissions are incorrect and cannot be set.
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
