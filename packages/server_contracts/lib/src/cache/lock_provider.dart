import 'dart:async';

import 'package:server_contracts/src/cache/lock.dart';

/// Creates and restores owner-aware locks for a cache backend.
///
/// The returned [Lock] is a handle; creating it does not necessarily acquire
/// the lock. Call [Lock.acquire], [Lock.get], or [Lock.block] before entering
/// the protected section.
abstract class LockProvider {
  /// Creates a lock handle named [name].
  ///
  /// [seconds] is the lock lease lifetime, while the timeout passed to
  /// [Lock.block] controls how long acquisition may wait. A positive value is
  /// recommended when the lock must eventually expire. The behavior of
  /// `seconds == 0` is backend-specific, so callers should not rely on it for
  /// recovery from abandoned work. When [owner] is omitted, the backend
  /// generates an owner identifier.
  FutureOr<Lock> lock(String name, [int seconds = 0, String? owner]);

  /// Restores a lock handle named [name] for an existing [owner].
  ///
  /// This does not claim the lock for a new owner. It is intended for code
  /// that already has the owner token returned by [Lock.owner] and needs to
  /// inspect or release that lock from another execution context.
  FutureOr<Lock> restoreLock(String name, String owner);
}
