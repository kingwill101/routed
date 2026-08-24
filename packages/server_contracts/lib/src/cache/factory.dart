import 'package:server_contracts/src/cache/repository.dart';

/// Creates cache repositories for named logical stores.
///
/// A factory hides the concrete store and repository implementation from code
/// that only needs to use a cache. Calling [store] without a name selects the
/// implementation's default repository.
///
/// ```dart
/// final sessions = factory.store('sessions');
/// await sessions.put('user:42', {'active': true});
/// ```
// A single method is intentional: this is the complete construction contract
// for a named repository factory.
// ignore: one_member_abstracts
abstract class Factory {
  /// Returns the repository registered under [name].
  ///
  /// When [name] is omitted, returns the implementation's default repository.
  /// Implementations may throw when a supplied name is unknown.
  Repository store([String? name]);
}
