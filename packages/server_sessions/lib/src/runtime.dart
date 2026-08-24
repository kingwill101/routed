import 'package:file/file.dart' as fs;
import 'package:server_contracts/server_contracts.dart' show Repository;

import 'cache_store.dart';
import 'cookie_store.dart';
import 'filesystem_store.dart';
import 'memory_store.dart';
import 'options.dart';
import 'secure_cookie.dart';

/// Framework-agnostic factory for composing session store runtimes.
///
/// This consolidates construction of built-in session store implementations so
/// framework adapters can delegate runtime assembly without re-implementing
/// store wiring.
class SessionRuntimeFactory {
  /// Creates a factory with no configuration.
  const SessionRuntimeFactory();

  /// Builds cookie-backed session storage using [codecs].
  CookieStore cookie({required List<SecureCookie> codecs}) {
    return CookieStore(codecs: codecs);
  }

  /// Builds in-memory session storage.
  ///
  /// [defaultOptions] configure cookies and [lifetime] controls the
  /// server-side retention period.
  MemorySessionStore memory({
    required List<SecureCookie> codecs,
    required SessionOptions defaultOptions,
    required Duration lifetime,
  }) {
    return MemorySessionStore(
      codecs: codecs,
      defaultOptions: defaultOptions,
      lifetime: lifetime,
    );
  }

  /// Builds file-backed session storage.
  ///
  /// [storagePath] identifies the directory and [lottery] optionally enables
  /// opportunistic pruning.
  FilesystemStore file({
    required List<SecureCookie> codecs,
    required String storagePath,
    required SessionOptions defaultOptions,
    List<int>? lottery,
    fs.FileSystem? fileSystem,
  }) {
    return FilesystemStore(
      codecs: codecs,
      storageDir: storagePath,
      defaultOptions: defaultOptions,
      lottery: lottery,
      fileSystem: fileSystem,
    );
  }

  /// Builds cache-backed session storage.
  ///
  /// [repository] stores payloads, while [cachePrefix] namespaces their keys.
  CacheSessionStore cache({
    required Repository repository,
    required List<SecureCookie> codecs,
    required SessionOptions defaultOptions,
    required String cachePrefix,
    required Duration lifetime,
  }) {
    return CacheSessionStore(
      repository: repository,
      codecs: codecs,
      defaultOptions: defaultOptions,
      cachePrefix: cachePrefix,
      lifetime: lifetime,
    );
  }
}

/// Shared [SessionRuntimeFactory] for adapters that prefer function-style access.
const SessionRuntimeFactory sessionRuntimeFactory = SessionRuntimeFactory();
