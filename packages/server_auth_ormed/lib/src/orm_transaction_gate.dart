import 'dart:async';

import 'package:ormed/ormed.dart';

final Expando<OrmAuthTransactionGate> _transactionGates =
    Expando<OrmAuthTransactionGate>();

/// Returns the process-local transaction gate associated with [database].
///
/// Ormed tracks transaction depth on the database connection. Sharing this
/// gate across the core and organization adapters prevents independent stores
/// over one connection from interleaving root transactions.
OrmAuthTransactionGate transactionGateFor(OrmDatabase database) =>
    _transactionGates[database] ??= OrmAuthTransactionGate();

/// Serializes store operations for one Ormed database connection.
///
/// Transaction-capable drivers run each operation inside an Ormed transaction.
/// Drivers such as Cloudflare D1, which expose query builders and bulk
/// operations but no callback transaction boundary, run the operation without
/// a transaction while retaining per-database ordering in this process.
final class OrmAuthTransactionGate {
  /// Creates an empty transaction gate.
  OrmAuthTransactionGate();

  final Object _zoneKey = Object();
  Future<void> _tail = Future<void>.value();

  /// Runs [action] after earlier actions complete.
  ///
  /// When [database]'s driver supports transactions, the action is atomic.
  /// Otherwise it is only serialized with other actions using this gate.
  Future<T> run<T>(OrmDatabase database, Future<T> Function() action) {
    if (identical(Zone.current[_zoneKey], this)) {
      // A store may need to compose another operation while its operation is
      // open (for example, loading authentication-method inventory). The gate
      // remains re-entrant so the nested call cannot wait behind its root
      // operation. Transaction-capable drivers use a savepoint here.
      return database.driver.metadata.supportsTransactions
          ? database.transaction(action)
          : action();
    }
    final waitFor = _tail;
    final release = Completer<void>();
    _tail = waitFor.then((_) => release.future);
    return waitFor.then((_) async {
      try {
        return await runZoned(() {
          if (database.driver.metadata.supportsTransactions) {
            return database.transaction(action);
          }
          return action();
        }, zoneValues: <Object?, Object?>{_zoneKey: this});
      } finally {
        release.complete();
      }
    });
  }
}
