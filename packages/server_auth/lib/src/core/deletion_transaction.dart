import 'dart:async';

/// A process-local persistence component that can participate in a
/// compensating Admin deletion transaction.
///
/// This contract is intended only for in-memory test and development stores.
/// Durable adapters must use their database transaction instead.
abstract interface class AuthInMemoryTransactionParticipant {
  Object createInMemoryCheckpoint();

  FutureOr<void> restoreInMemoryCheckpoint(Object checkpoint);
}

/// Captured state for every plugin store participating in one user deletion.
final class AuthUserDataDeletionCheckpoint {
  AuthUserDataDeletionCheckpoint._(this._entries);

  factory AuthUserDataDeletionCheckpoint.capture(Iterable<Object> stores) {
    final entries = <_CheckpointEntry>[];
    for (final store in stores) {
      if (store is! AuthInMemoryTransactionParticipant) {
        throw StateError(
          '${store.runtimeType} cannot participate in the in-memory Admin '
          'deletion transaction.',
        );
      }
      entries.add(_CheckpointEntry(store, store.createInMemoryCheckpoint()));
    }
    return AuthUserDataDeletionCheckpoint._(entries);
  }

  final List<_CheckpointEntry> _entries;

  Future<void> restore() async {
    for (final entry in _entries.reversed) {
      await entry.participant.restoreInMemoryCheckpoint(entry.checkpoint);
    }
  }
}

final class _CheckpointEntry {
  const _CheckpointEntry(this.participant, this.checkpoint);

  final AuthInMemoryTransactionParticipant participant;
  final Object checkpoint;
}
