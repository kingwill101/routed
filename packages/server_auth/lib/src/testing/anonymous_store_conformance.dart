import 'dart:async';

import '../core/anonymous_store.dart';
import '../core/models.dart';
import '../core/store.dart';

typedef AuthAnonymousStoreConformanceFactory =
    FutureOr<AuthAnonymousStoreConformanceFixture> Function();

enum AuthAnonymousStoreConformanceFaultPoint {
  afterCreateWrite,
  duringDelete,
  duringUpgrade,
}

abstract interface class AuthAnonymousStoreConformanceFaultController {
  void failNext(AuthAnonymousStoreConformanceFaultPoint point);
}

final class AuthAnonymousStoreConformanceFixture {
  const AuthAnonymousStoreConformanceFixture({
    required this.store,
    required this.mutations,
    required this.faults,
    this.dispose,
  });

  final AuthStore store;
  final AuthAnonymousAccountMutationStore mutations;
  final AuthAnonymousStoreConformanceFaultController faults;
  final FutureOr<void> Function()? dispose;
}

final class AuthAnonymousStoreConformanceFailure implements Exception {
  const AuthAnonymousStoreConformanceFailure(this.caseId, this.cause);

  final String caseId;
  final Object cause;

  @override
  String toString() => 'AuthAnonymousStoreConformanceFailure($caseId): $cause';
}

final class AuthAnonymousStoreConformanceCase {
  const AuthAnonymousStoreConformanceCase({
    required this.id,
    required this.description,
    required Future<void> Function() run,
  }) : _run = run;

  final String id;
  final String description;
  final Future<void> Function() _run;

  Future<void> run() => _run();
}

/// Reusable atomicity contract for anonymous-account persistence adapters.
///
/// Durable adapters should run every case against their real transaction
/// implementation and wire [AuthAnonymousStoreConformanceFaultController] to
/// database fault injection. The suite never accepts an in-memory fallback.
final class AuthAnonymousStoreConformanceSuite {
  AuthAnonymousStoreConformanceSuite(this.createFixture);

  final AuthAnonymousStoreConformanceFactory createFixture;

  List<AuthAnonymousStoreConformanceCase> get cases => [
    _case(
      'create_replay',
      'Creation is atomic and replay-safe.',
      _createReplay,
    ),
    _case(
      'create_contention',
      'Concurrent creation commits exactly one identity.',
      _createContention,
    ),
    _case(
      'create_rollback',
      'Creation rolls back a fault after its user write.',
      _createRollback,
    ),
    _case(
      'delete_contention',
      'Authenticated deletion commits once under contention.',
      _deleteContention,
    ),
    _case(
      'delete_rollback',
      'Deletion restores the anonymous identity after a transaction fault.',
      _deleteRollback,
    ),
    _case(
      'upgrade_replay',
      'Upgrade finalization preserves its target and replays safely.',
      _upgradeReplay,
    ),
    _case(
      'upgrade_rollback',
      'Upgrade finalization restores its source after a transaction fault.',
      _upgradeRollback,
    ),
    _case(
      'upgrade_target_binding',
      'Upgrade replay receipts cannot be rebound to another target.',
      _upgradeTargetBinding,
    ),
  ];

  AuthAnonymousStoreConformanceCase _case(
    String id,
    String description,
    Future<void> Function(AuthAnonymousStoreConformanceFixture fixture) body,
  ) => AuthAnonymousStoreConformanceCase(
    id: id,
    description: description,
    run: () => _withFixture(id, body),
  );

  Future<void> _withFixture(
    String id,
    Future<void> Function(AuthAnonymousStoreConformanceFixture fixture) body,
  ) async {
    final fixture = await Future.sync(createFixture);
    try {
      await body(fixture);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AuthAnonymousStoreConformanceFailure(id, error),
        stackTrace,
      );
    } finally {
      await Future.sync(() => fixture.dispose?.call());
    }
  }

  Future<void> _createReplay(
    AuthAnonymousStoreConformanceFixture fixture,
  ) async {
    final command = _createCommand('create-replay');
    final first = await fixture.mutations.createAnonymousAccount(command);
    final second = await fixture.mutations.createAnonymousAccount(command);
    _require(
      first.status == AuthAnonymousMutationStatus.applied,
      'not applied',
    );
    _require(
      second.status == AuthAnonymousMutationStatus.replayed,
      'not replayed',
    );
    _require(first.user?.id == second.user?.id, 'replay changed the user');
    final mismatch = await fixture.mutations.createAnonymousAccount(
      AuthAnonymousCreateAccountCommand(
        operationId: command.operationId,
        user: AuthUser(id: 'different-user', isAnonymous: true),
      ),
    );
    _require(
      mismatch.status == AuthAnonymousMutationStatus.replayMismatch,
      'operation ID was rebound',
    );
  }

  Future<void> _createContention(
    AuthAnonymousStoreConformanceFixture fixture,
  ) async {
    final command = _createCommand('create-contention');
    final results = await Future.wait(
      List<Future<AuthAnonymousMutationResult>>.generate(
        16,
        (_) => Future.sync(
          () => fixture.mutations.createAnonymousAccount(command),
        ),
      ),
    );
    _require(
      results
              .where(
                (result) =>
                    result.status == AuthAnonymousMutationStatus.applied,
              )
              .length ==
          1,
      'contention committed more than once',
    );
    _require(
      results.every((result) => result.committed),
      'contention returned a non-committed result',
    );
  }

  Future<void> _createRollback(
    AuthAnonymousStoreConformanceFixture fixture,
  ) async {
    final command = _createCommand('create-rollback');
    fixture.faults.failNext(
      AuthAnonymousStoreConformanceFaultPoint.afterCreateWrite,
    );
    await _requireThrows(
      () => fixture.mutations.createAnonymousAccount(command),
      'injected creation fault did not escape',
    );
    _require(
      await fixture.store.users.findById(command.user.id) == null,
      'failed creation persisted a user',
    );
    final retry = await fixture.mutations.createAnonymousAccount(command);
    _require(
      retry.status == AuthAnonymousMutationStatus.applied,
      'rolled-back creation could not retry',
    );
  }

  Future<void> _deleteContention(
    AuthAnonymousStoreConformanceFixture fixture,
  ) async {
    final user = await _create(fixture, 'delete-contention');
    final now = DateTime.utc(2030);
    await fixture.store.sessions.create(
      AuthSessionRecord(
        id: 'delete-contention-session',
        tokenHash: 'delete-contention-token-digest',
        userId: user.id,
        createdAt: now,
        expiresAt: now.add(const Duration(days: 1)),
        lastUsedAt: now,
        authenticationMethod: 'anonymous',
      ),
    );
    final command = AuthAnonymousDeleteAccountCommand(
      operationId: 'delete-contention-finalize-operation',
      userId: user.id,
    );
    final results = await Future.wait(
      List<Future<AuthAnonymousMutationResult>>.generate(
        12,
        (_) => Future.sync(
          () => fixture.mutations.deleteAnonymousAccount(command),
        ),
      ),
    );
    _require(
      results
              .where(
                (result) =>
                    result.status == AuthAnonymousMutationStatus.applied,
              )
              .length ==
          1,
      'deletion committed more than once',
    );
    _require(
      results.every((result) => result.committed),
      'delete did not replay',
    );
    _require(
      results.every((result) => result.user == null),
      'deletion replay retained user data',
    );
    _require(
      await fixture.store.users.findById(user.id) == null,
      'deleted user survived',
    );
    _require(
      (await fixture.store.sessions.listForUser(user.id)).isEmpty,
      'deleted user session survived',
    );
  }

  Future<void> _deleteRollback(
    AuthAnonymousStoreConformanceFixture fixture,
  ) async {
    final createCommand = _createCommand('delete-rollback');
    final user = (await fixture.mutations.createAnonymousAccount(
      createCommand,
    )).user!;
    final command = AuthAnonymousDeleteAccountCommand(
      operationId: 'delete-rollback-finalize-operation',
      userId: user.id,
    );
    fixture.faults.failNext(
      AuthAnonymousStoreConformanceFaultPoint.duringDelete,
    );
    await _requireThrows(
      () => fixture.mutations.deleteAnonymousAccount(command),
      'injected deletion fault did not escape',
    );
    _require(
      await fixture.store.users.findById(user.id) != null,
      'failed deletion removed the user',
    );
    _require(
      (await fixture.mutations.createAnonymousAccount(createCommand)).status ==
          AuthAnonymousMutationStatus.replayed,
      'failed deletion lost the creation replay receipt',
    );
    final retry = await fixture.mutations.deleteAnonymousAccount(command);
    _require(
      retry.status == AuthAnonymousMutationStatus.applied,
      'retry failed',
    );
  }

  Future<void> _upgradeReplay(
    AuthAnonymousStoreConformanceFixture fixture,
  ) async {
    final source = await _create(fixture, 'upgrade-replay');
    final target = await fixture.store.users.create(
      AuthUser(id: 'upgrade-target', email: 'target@example.com'),
    );
    final command = AuthAnonymousCompleteUpgradeCommand(
      operationId: 'upgrade-replay-finalize-operation',
      anonymousUserId: source.id,
      targetUserId: target.id,
    );
    final first = await fixture.mutations.completeAnonymousAccountUpgrade(
      command,
    );
    final second = await fixture.mutations.completeAnonymousAccountUpgrade(
      command,
    );
    _require(
      first.status == AuthAnonymousMutationStatus.applied,
      'not applied',
    );
    _require(
      second.status == AuthAnonymousMutationStatus.replayed,
      'not replayed',
    );
    _require(second.user == null, 'upgrade replay retained source user data');
    _require(
      await fixture.store.users.findById(source.id) == null,
      'source survived upgrade',
    );
    _require(
      await fixture.store.users.findById(target.id) != null,
      'target was deleted',
    );
  }

  Future<void> _upgradeRollback(
    AuthAnonymousStoreConformanceFixture fixture,
  ) async {
    final createCommand = _createCommand('upgrade-rollback');
    final source = (await fixture.mutations.createAnonymousAccount(
      createCommand,
    )).user!;
    final target = await fixture.store.users.create(
      AuthUser(id: 'upgrade-rollback-target'),
    );
    final command = AuthAnonymousCompleteUpgradeCommand(
      operationId: 'upgrade-rollback-finalize-operation',
      anonymousUserId: source.id,
      targetUserId: target.id,
    );
    fixture.faults.failNext(
      AuthAnonymousStoreConformanceFaultPoint.duringUpgrade,
    );
    await _requireThrows(
      () => fixture.mutations.completeAnonymousAccountUpgrade(command),
      'injected upgrade fault did not escape',
    );
    _require(
      await fixture.store.users.findById(source.id) != null,
      'failed upgrade removed its source',
    );
    _require(
      await fixture.store.users.findById(target.id) != null,
      'failed upgrade removed its target',
    );
    _require(
      (await fixture.mutations.createAnonymousAccount(createCommand)).status ==
          AuthAnonymousMutationStatus.replayed,
      'failed upgrade lost the creation replay receipt',
    );
  }

  Future<void> _upgradeTargetBinding(
    AuthAnonymousStoreConformanceFixture fixture,
  ) async {
    final source = await _create(fixture, 'upgrade-binding-source');
    const operationId = 'upgrade-target-binding-finalize';
    final first = await fixture.mutations.completeAnonymousAccountUpgrade(
      AuthAnonymousCompleteUpgradeCommand(
        operationId: operationId,
        anonymousUserId: source.id,
        targetUserId: 'stateless-target-a',
      ),
    );
    _require(
      first.status == AuthAnonymousMutationStatus.applied,
      'stateless target was not accepted',
    );
    final rebound = await fixture.mutations.completeAnonymousAccountUpgrade(
      AuthAnonymousCompleteUpgradeCommand(
        operationId: operationId,
        anonymousUserId: source.id,
        targetUserId: 'stateless-target-b',
      ),
    );
    _require(
      rebound.status == AuthAnonymousMutationStatus.replayMismatch,
      'operation receipt was rebound to another target',
    );
  }

  Future<AuthUser> _create(
    AuthAnonymousStoreConformanceFixture fixture,
    String id,
  ) async {
    final result = await fixture.mutations.createAnonymousAccount(
      _createCommand(id),
    );
    return result.user!;
  }
}

AuthAnonymousCreateAccountCommand _createCommand(String id) =>
    AuthAnonymousCreateAccountCommand(
      operationId: '$id-operation',
      user: AuthUser(id: '$id-user', name: 'Guest', isAnonymous: true),
    );

Future<void> _requireThrows(
  FutureOr<Object?> Function() operation,
  String message,
) async {
  try {
    await Future.sync(operation);
  } catch (_) {
    return;
  }
  throw StateError(message);
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
