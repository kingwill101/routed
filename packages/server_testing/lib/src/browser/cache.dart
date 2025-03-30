import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

/// A simple file-based cache for storing downloaded resources keyed by URL.
///
/// Useful for caching assets or potentially browser binaries, although browser
/// binaries are typically managed by the [Registry]. Uses SHA256 hash of the URL
/// as the filename for cached content.
class BrowserCache {
  /// The directory where cached files are stored.
  final String cacheDir;

  /// Creates a [BrowserCache] instance that will store files in [cacheDir].
  BrowserCache(this.cacheDir);

  /// Initializes the cache by ensuring the [cacheDir] exists.
  /// Creates the directory recursively if it doesn't exist.
  Future<void> init() async {
    await Directory(cacheDir).create(recursive: true);
  }

  /// Generates a cache key (filename) for a given [url] by computing its SHA256 hash.
  String _getCacheKey(String url) {
    return sha256.convert(utf8.encode(url)).toString();
  }

  /// Retrieves a cached file for the specified [url].
  ///
  /// Calculates the cache key using [_getCacheKey] and checks if the corresponding
  /// file exists in the [cacheDir]. Returns the [File] object if found,
  /// otherwise returns `null`.
  Future<File?> getCachedFile(String url) async {
    final key = _getCacheKey(url);
    final file = File(path.join(cacheDir, key));
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  /// Stores the given [bytes] in the cache, associated with the specified [url].
  ///
  /// Calculates the cache key, creates the file in the [cacheDir], and writes
  /// the [bytes] to it. Overwrites any existing file with the same key.
  Future<void> cacheFile(String url, List<int> bytes) async {
    final key = _getCacheKey(url);
    final file = File(path.join(cacheDir, key));
    await file.writeAsBytes(bytes);
  }

  /// Removes the entire cache directory and all its contents.
  Future<void> clear() async {
    if (await Directory(cacheDir).exists()) {
      await Directory(cacheDir).delete(recursive: true);
    }
  }
}
