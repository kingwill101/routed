import 'dart:async';

import '../core/api_key.dart';
import '../core/tokens.dart';

typedef AuthApiKeyStoreConformanceFactory =
    FutureOr<AuthApiKeyStoreConformanceFixture> Function({int maxRecords});

enum AuthApiKeyStoreConformanceFaultPoint { afterRotationInsert }

abstract interface class AuthApiKeyStoreConformanceFaultController {
  void failNext(AuthApiKeyStoreConformanceFaultPoint point);
}

final class AuthApiKeyStoreConformanceFixture {
  const AuthApiKeyStoreConformanceFixture({
    required this.store,
    required this.faults,
    this.dispose,
  });

  final AuthApiKeyStore store;
  final AuthApiKeyStoreConformanceFaultController faults;
  final FutureOr<void> Function()? dispose;
}

final class AuthApiKeyStoreConformanceFailure implements Exception {
  const AuthApiKeyStoreConformanceFailure(this.caseId, this.cause);

  final String caseId;
  final Object cause;

  @override
  String toString() => 'AuthApiKeyStoreConformanceFailure($caseId): $cause';
}

final class AuthApiKeyStoreConformanceCase {
  const AuthApiKeyStoreConformanceCase({
    required this.id,
    required this.description,
    required Future<void> Function() run,
  }) : _run = run;

  final String id;
  final String description;
  final Future<void> Function() _run;

  Future<void> run() => _run();
}

/// Reusable lifecycle, bound, contention, and rollback contract for API keys.
final class AuthApiKeyStoreConformanceSuite {
  AuthApiKeyStoreConformanceSuite(this.createFixture);

  final AuthApiKeyStoreConformanceFactory createFixture;

  List<AuthApiKeyStoreConformanceCase> get cases => [
    _case(
      'create_and_list',
      'Create persists safe key metadata.',
      _createAndList,
    ),
    _case(
      'touch_active',
      'Only active keys can advance last-use.',
      _touchActive,
    ),
    _case('revoke_owner', 'Revocation enforces exact ownership.', _revokeOwner),
    _case(
      'rotate_atomic',
      'Rotation replaces one active key atomically.',
      _rotateAtomic,
    ),
    _case(
      'rotation_bound',
      'Rotation never exceeds maxRecords.',
      _rotationBound,
      maxRecords: 1,
    ),
    _case(
      'rotation_binding',
      'Rotation rejects foreign and expired replacements.',
      _rotationBinding,
    ),
    _case(
      'rotation_collision',
      'Rotation rejects an existing replacement ID without mutation.',
      _rotationCollision,
    ),
    _case(
      'create_contention',
      'A duplicate key ID commits once.',
      _createContention,
    ),
    _case(
      'rotation_rollback',
      'A post-insert fault restores the old key.',
      _rotationRollback,
    ),
  ];

  AuthApiKeyStoreConformanceCase _case(
    String id,
    String description,
    Future<void> Function(AuthApiKeyStoreConformanceFixture fixture) body, {
    int maxRecords = 10000,
  }) => AuthApiKeyStoreConformanceCase(
    id: id,
    description: description,
    run: () => _withFixture(id, maxRecords, body),
  );

  Future<void> _withFixture(
    String id,
    int maxRecords,
    Future<void> Function(AuthApiKeyStoreConformanceFixture fixture) body,
  ) async {
    final fixture = await Future.sync(
      () => createFixture(maxRecords: maxRecords),
    );
    try {
      await body(fixture);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AuthApiKeyStoreConformanceFailure(id, error),
        stackTrace,
      );
    } finally {
      await Future.sync(() => fixture.dispose?.call());
    }
  }

  Future<void> _createAndList(AuthApiKeyStoreConformanceFixture fixture) async {
    final record = _record('create');
    await fixture.store.create(record);
    final found = await fixture.store.findById(record.id);
    _require(found?.secretHash == record.secretHash, 'digest changed');
    _require(found?.secretHash != 'raw-create-secret', 'raw key persisted');
    final listed = await fixture.store.listForUser(record.userId);
    _require(
      listed.length == 1 && listed.single.id == record.id,
      'list drifted',
    );
    _require(
      (await fixture.store.listForUser('other')).isEmpty,
      'owner leaked',
    );
  }

  Future<void> _touchActive(AuthApiKeyStoreConformanceFixture fixture) async {
    final active = _record('active');
    final expired = _record(
      'expired',
      expiresAt: _now.subtract(const Duration(minutes: 1)),
    );
    await fixture.store.create(active);
    await fixture.store.create(expired);
    final touched = await fixture.store.touchIfActive(
      active.id,
      _now.add(const Duration(minutes: 1)),
    );
    _require(
      touched?.lastUsedAt == _now.add(const Duration(minutes: 1)),
      'not touched',
    );
    _require(
      await fixture.store.touchIfActive(expired.id, _now) == null,
      'expired key touched',
    );
  }

  Future<void> _revokeOwner(AuthApiKeyStoreConformanceFixture fixture) async {
    final record = _record('revoke');
    await fixture.store.create(record);
    _require(
      await fixture.store.revokeForUser('other', record.id, revokedAt: _now) ==
          null,
      'foreign owner revoked key',
    );
    final revoked = await fixture.store.revokeForUser(
      record.userId,
      record.id,
      revokedAt: _now,
    );
    _require(revoked?.revokedAt == _now, 'owner revocation did not persist');
    _require(
      await fixture.store.touchIfActive(record.id, _now) == null,
      'revoked key touched',
    );
  }

  Future<void> _rotateAtomic(AuthApiKeyStoreConformanceFixture fixture) async {
    final old = _record('rotate-old');
    final replacement = _record('rotate-new');
    await fixture.store.create(old);
    final rotated = await fixture.store.rotateForUser(
      userId: old.userId,
      id: old.id,
      replacement: replacement,
      revokedAt: _now,
    );
    _require(rotated?.id == replacement.id, 'replacement did not commit');
    _require(
      await fixture.store.touchIfActive(old.id, _now) == null,
      'old key active',
    );
    _require(
      await fixture.store.touchIfActive(replacement.id, _now) != null,
      'replacement inactive',
    );
    _require(
      await fixture.store.rotateForUser(
            userId: old.userId,
            id: old.id,
            replacement: _record('rotate-third'),
            revokedAt: _now,
          ) ==
          null,
      'single-use rotation replayed',
    );
  }

  Future<void> _rotationBound(AuthApiKeyStoreConformanceFixture fixture) async {
    var current = _record('bound-0');
    await fixture.store.create(current);
    for (var index = 1; index <= 32; index++) {
      final replacement = _record('bound-$index');
      _require(
        await fixture.store.rotateForUser(
              userId: current.userId,
              id: current.id,
              replacement: replacement,
              revokedAt: _now,
            ) !=
            null,
        'bounded rotation $index failed',
      );
      _require(
        (await fixture.store.listForUser(current.userId)).length == 1,
        'rotation $index exceeded maxRecords',
      );
      _require(
        await fixture.store.touchIfActive(current.id, _now) == null,
        'rotation $index retained the old key',
      );
      current = replacement;
    }
  }

  Future<void> _rotationBinding(
    AuthApiKeyStoreConformanceFixture fixture,
  ) async {
    final old = _record('binding-old');
    await fixture.store.create(old);
    final foreign = _record('binding-foreign', userId: 'user-2');
    final expired = _record(
      'binding-expired',
      expiresAt: _now.subtract(const Duration(seconds: 1)),
    );
    final revoked = _record('binding-revoked', revokedAt: _now);
    _require(
      await fixture.store.rotateForUser(
            userId: old.userId,
            id: old.id,
            replacement: foreign,
            revokedAt: _now,
          ) ==
          null,
      'foreign replacement committed',
    );
    _require(
      await fixture.store.rotateForUser(
            userId: old.userId,
            id: old.id,
            replacement: expired,
            revokedAt: _now,
          ) ==
          null,
      'expired replacement committed',
    );
    _require(
      await fixture.store.rotateForUser(
            userId: old.userId,
            id: old.id,
            replacement: revoked,
            revokedAt: _now,
          ) ==
          null,
      'revoked replacement committed',
    );
    _require(
      await fixture.store.touchIfActive(old.id, _now) != null,
      'rejected replacement revoked the old key',
    );
  }

  Future<void> _rotationCollision(
    AuthApiKeyStoreConformanceFixture fixture,
  ) async {
    final old = _record('collision-old');
    final occupied = _record('collision-occupied');
    await fixture.store.create(old);
    await fixture.store.create(occupied);

    _require(
      await fixture.store.rotateForUser(
            userId: old.userId,
            id: old.id,
            replacement: occupied,
            revokedAt: _now,
          ) ==
          null,
      'existing replacement ID committed',
    );
    _require(
      await fixture.store.touchIfActive(old.id, _now) != null,
      'collision revoked the old key',
    );
    _require(
      await fixture.store.touchIfActive(occupied.id, _now) != null,
      'collision changed the occupied key',
    );
  }

  Future<void> _createContention(
    AuthApiKeyStoreConformanceFixture fixture,
  ) async {
    final record = _record('contended');
    final results = await Future.wait([
      for (var index = 0; index < 16; index++)
        Future.sync(() async {
          try {
            await fixture.store.create(record);
            return true;
          } catch (_) {
            return false;
          }
        }),
    ]);
    _require(
      results.where((committed) => committed).length == 1,
      'duplicate committed',
    );
    _require(
      (await fixture.store.listForUser(record.userId)).length == 1,
      'duplicate rows',
    );
  }

  Future<void> _rotationRollback(
    AuthApiKeyStoreConformanceFixture fixture,
  ) async {
    final old = _record('rollback-old');
    final replacement = _record('rollback-new');
    await fixture.store.create(old);
    fixture.faults.failNext(
      AuthApiKeyStoreConformanceFaultPoint.afterRotationInsert,
    );
    await _requireThrows(
      () => fixture.store.rotateForUser(
        userId: old.userId,
        id: old.id,
        replacement: replacement,
        revokedAt: _now,
      ),
      'injected rotation fault did not escape',
    );
    _require(
      await fixture.store.touchIfActive(old.id, _now) != null,
      'old key lost',
    );
    _require(
      await fixture.store.findById(replacement.id) == null,
      'replacement leaked',
    );
  }
}

final DateTime _now = DateTime.utc(2030, 1, 1);

AuthApiKeyRecord _record(
  String suffix, {
  String userId = 'user-1',
  DateTime? expiresAt,
  DateTime? revokedAt,
}) => AuthApiKeyRecord(
  id: 'key-$suffix',
  userId: userId,
  name: 'Key $suffix',
  keyPrefix: 'rka.key-$suffix',
  secretHash: hashOpaqueToken('raw-$suffix-secret'),
  scopes: const ['jobs:read', 'jobs:write'],
  createdAt: _now.subtract(const Duration(minutes: 2)),
  updatedAt: _now.subtract(const Duration(minutes: 2)),
  expiresAt: expiresAt ?? _now.add(const Duration(days: 1)),
  revokedAt: revokedAt,
);

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _requireThrows(
  FutureOr<Object?> Function() action,
  String message,
) async {
  try {
    await Future.sync(action);
  } catch (_) {
    return;
  }
  throw StateError(message);
}
