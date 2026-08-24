/// Framework-agnostic contracts shared by server packages.
///
/// This library defines the interfaces used to connect cache repositories,
/// configuration stores, and translation services without coupling those
/// services to a particular HTTP framework or runtime. Implementations are
/// provided by packages such as `server_data`, `server_auth`, and framework
/// adapters.
///
/// The main contract groups are:
///
/// * [Config] for typed access to a mutable configuration tree.
/// * [Repository] and the cache contracts for key-value storage and locks.
/// * [TranslationLoader] and [TranslatorContract] for locale-aware messages.
///
/// Import this library when an application or adapter needs the contracts but
/// should not depend on a concrete implementation.
///
/// ```dart
/// import 'package:server_contracts/server_contracts.dart';
///
/// Future<Object?> readHealth(Repository repository) {
///   return repository.get('health');
/// }
/// ```
library;

import 'package:server_contracts/src/cache/repository.dart' show Repository;
import 'package:server_contracts/src/config/config.dart' show Config;
import 'package:server_contracts/src/translation/loader.dart'
    show TranslationLoader;
import 'package:server_contracts/src/translation/translator.dart'
    show TranslatorContract;

export 'src/cache/cache.dart';
export 'src/config/config.dart';
export 'src/translation/loader.dart';
export 'src/translation/translator.dart';
