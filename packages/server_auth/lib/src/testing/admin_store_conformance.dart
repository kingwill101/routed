import 'dart:async';

import '../core/admin_models.dart';
import '../core/admin_store.dart';
import '../core/exceptions.dart';
import '../core/models.dart';
import '../core/store.dart';

typedef AuthAdminStoreConformanceFixtureFactory =
    FutureOr<AuthAdminStoreConformanceFixture> Function();

enum AuthAdminStoreConformanceFaultPoint { afterMutation }

abstract interface class AuthAdminStoreConformanceFaultControl {
  FutureOr<void> failNext(AuthAdminStoreConformanceFaultPoint point);
}

final class AuthAdminStoreConformanceFixture {
  const AuthAdminStoreConformanceFixture({
    required this.coreStore,
    required this.adminStore,
    this.faultControl,
    this.dispose,
  });

  final AuthStore coreStore;
  final AuthAdminStore adminStore;
  final AuthAdminStoreConformanceFaultControl? faultControl;
  final FutureOr<void> Function()? dispose;
}

final class AuthAdminStoreConformanceResult {
  const AuthAdminStoreConformanceResult.passed() : skippedReason = null;
  const AuthAdminStoreConformanceResult.skipped(this.skippedReason);

  final String? skippedReason;
  bool get isSkipped => skippedReason != null;
}

final class AuthAdminStoreConformanceFailure implements Exception {
  const AuthAdminStoreConformanceFailure({
    required this.caseId,
    required this.cause,
  });

  final String caseId;
  final Object cause;

  @override
  String toString() => 'AuthAdminStoreConformanceFailure($caseId): $cause';
}

final class AuthAdminStoreConformanceCase {
  const AuthAdminStoreConformanceCase._({
    required this.id,
    required this.description,
    required Future<AuthAdminStoreConformanceResult> Function() run,
  }) : _run = run;

  final String id;
  final String description;
  final Future<AuthAdminStoreConformanceResult> Function() _run;

  Future<AuthAdminStoreConformanceResult> run() => _run();
}

/// Reusable security contract for durable [AuthAdminStore] implementations.
///
/// Each case uses a fresh persistence namespace. Adapters should provide a
/// test-only [AuthAdminStoreConformanceFaultControl] so rollback is verified at
/// a real transaction fault point; that case is skipped when unavailable.
final class AuthAdminStoreConformanceSuite {
  AuthAdminStoreConformanceSuite({
    required AuthAdminStoreConformanceFixtureFactory createFixture,
  }) : _createFixture = createFixture;

  final AuthAdminStoreConformanceFixtureFactory _createFixture;

  late final List<AuthAdminStoreConformanceCase> cases =
      List<AuthAdminStoreConformanceCase>.unmodifiable(<
        AuthAdminStoreConformanceCase
      >[
        _case(
          id: 'admin.authorization.stale-role',
          description:
              'revalidates administrator permissions inside the mutation',
          verify: _verifyStaleRoleAuthorization,
        ),
        _case(
          id: 'admin.credentials.rollback',
          description:
              'rolls credentials, sessions, and JWT versions back together',
          requiresFaultControl: true,
          verify: _verifyCredentialRollback,
        ),
        _case(
          id: 'admin.access.global-revocation',
          description:
              'revokes all server sessions and rotates JWT versions atomically',
          verify: _verifyGlobalRevocation,
        ),
        _case(
          id: 'admin.user-update.contention',
          description: 'rejects a stale concurrent user replacement',
          verify: _verifyUserUpdateContention,
        ),
      ]);

  AuthAdminStoreConformanceCase _case({
    required String id,
    required String description,
    required Future<void> Function(AuthAdminStoreConformanceFixture fixture)
    verify,
    bool requiresFaultControl = false,
  }) => AuthAdminStoreConformanceCase._(
    id: id,
    description: description,
    run: () async {
      final fixture = await Future.sync(_createFixture);
      try {
        if (requiresFaultControl && fixture.faultControl == null) {
          return const AuthAdminStoreConformanceResult.skipped(
            'Adapter fixture does not expose transaction fault injection.',
          );
        }
        try {
          await verify(fixture);
        } catch (error, stackTrace) {
          Error.throwWithStackTrace(
            AuthAdminStoreConformanceFailure(caseId: id, cause: error),
            stackTrace,
          );
        }
        return const AuthAdminStoreConformanceResult.passed();
      } finally {
        await Future.sync(() => fixture.dispose?.call());
      }
    },
  );
}

Future<void> _verifyStaleRoleAuthorization(
  AuthAdminStoreConformanceFixture fixture,
) async {
  final first = _user('admin-first', role: 'admin');
  final second = _user('admin-second', role: 'admin');
  final target = _user('target');
  await _seed(fixture.coreStore, first);
  await _seed(fixture.coreStore, second);
  await _seed(fixture.coreStore, target);
  await fixture.adminStore.execute(
    AuthAdminReplaceRolesMutation(
      authorization: _authorization(second.id, 'set-role'),
      userId: first.id,
      roles: const <String>['user'],
    ),
  );

  final staleWrite = AuthAdminUpdateUserMutation(
    authorization: _authorization(first.id, 'update'),
    expectedUser: target,
    user: AuthUser(
      id: target.id,
      email: target.email,
      name: 'must not commit',
      roles: target.roles,
    ),
    revokeAccess: false,
  );
  await _expectFlow(
    () => fixture.adminStore.execute(staleWrite),
    'admin_forbidden',
  );
  _check(
    (await fixture.coreStore.users.findById(target.id))?.name == null,
    'stale administrator mutation committed',
  );
}

Future<void> _verifyCredentialRollback(
  AuthAdminStoreConformanceFixture fixture,
) async {
  final administrator = _user('admin', role: 'admin');
  final target = _user('target');
  await _seed(fixture.coreStore, administrator);
  await _seed(fixture.coreStore, target);
  final now = DateTime.utc(2030);
  await fixture.coreStore.sessions.create(
    AuthSessionRecord(
      id: 'target-session',
      tokenHash: 'target-session-hash',
      userId: target.id,
      createdAt: now,
      expiresAt: now.add(const Duration(days: 1)),
      lastUsedAt: now,
      authenticationMethod: 'credentials',
    ),
  );
  final beforeVersion = await fixture.coreStore.jwtVersions.current(target.id);
  await fixture.faultControl!.failNext(
    AuthAdminStoreConformanceFaultPoint.afterMutation,
  );
  var failed = false;
  try {
    await fixture.adminStore.execute(
      AuthAdminSetPasswordMutation(
        authorization: _authorization(administrator.id, 'set-password'),
        userId: target.id,
        credential: AuthPasswordCredential(
          id: 'replacement-credential',
          userId: target.id,
          identifier: target.email!,
          passwordHash: 'encoded-replacement',
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
  } catch (_) {
    failed = true;
  }
  _check(failed, 'faulted credential mutation unexpectedly succeeded');
  _check(
    (await fixture.coreStore.credentials.findByIdentifier(
          target.email!,
        ))?.passwordHash ==
        'encoded-initial',
    'credential write was not rolled back',
  );
  _check(
    (await fixture.coreStore.sessions.listForUser(target.id)).single.isActive(),
    'session revocation was not rolled back',
  );
  _check(
    await fixture.coreStore.jwtVersions.current(target.id) == beforeVersion,
    'JWT rotation was not rolled back',
  );
  _check(
    (await fixture.adminStore.listAuditRecords()).isEmpty,
    'audit fact was committed for a rolled-back mutation',
  );
}

Future<void> _verifyGlobalRevocation(
  AuthAdminStoreConformanceFixture fixture,
) async {
  final administrator = _user('admin', role: 'admin');
  final target = _user('target');
  await _seed(fixture.coreStore, administrator);
  await _seed(fixture.coreStore, target);
  final now = DateTime.utc(2030);
  await fixture.coreStore.sessions.create(
    AuthSessionRecord(
      id: 'target-session',
      tokenHash: 'target-session-hash',
      userId: target.id,
      createdAt: now,
      expiresAt: now.add(const Duration(days: 1)),
      lastUsedAt: now,
      authenticationMethod: 'credentials',
    ),
  );
  final beforeVersion = await fixture.coreStore.jwtVersions.current(target.id);
  await fixture.adminStore.execute(
    AuthAdminRevokeSessionsMutation(
      authorization: _authorization(
        administrator.id,
        'revoke',
        resource: 'session',
      ),
      userId: target.id,
    ),
  );
  _check(
    !(await fixture.coreStore.sessions.listForUser(
      target.id,
    )).single.isActive(),
    'server session remained active',
  );
  _check(
    await fixture.coreStore.jwtVersions.current(target.id) == beforeVersion + 1,
    'JWT version did not rotate',
  );
  final audit = await fixture.adminStore.listAuditRecords(
    targetUserId: target.id,
  );
  _check(audit.length == 1, 'mutation audit fact was not committed');
  _check(
    audit.single.operation == 'admin.revokeUserSessions' &&
        audit.single.initiatorUserId == administrator.id,
    'mutation audit fact does not match the committed command',
  );
}

Future<void> _verifyUserUpdateContention(
  AuthAdminStoreConformanceFixture fixture,
) async {
  final administrator = _user('admin', role: 'admin');
  final target = _user('target');
  await _seed(fixture.coreStore, administrator);
  await _seed(fixture.coreStore, target);
  final results = await Future.wait(<Future<String?>>[
    _captureFlow(
      () => fixture.adminStore.execute(
        _update(administrator.id, target, 'first'),
      ),
    ),
    _captureFlow(
      () => fixture.adminStore.execute(
        _update(administrator.id, target, 'second'),
      ),
    ),
  ]);
  _check(
    results.where((result) => result == null).length == 1,
    'contention committed more than one stale user replacement',
  );
  _check(
    results.where((result) => result == 'stale_user_state').length == 1,
    'contention did not reject the stale replacement',
  );
}

AuthAdminUpdateUserMutation _update(
  String actorId,
  AuthUser target,
  String name,
) => AuthAdminUpdateUserMutation(
  authorization: _authorization(actorId, 'update'),
  expectedUser: target,
  user: AuthUser(
    id: target.id,
    email: target.email,
    name: name,
    roles: target.roles,
  ),
  revokeAccess: false,
);

AuthAdminMutationAuthorization _authorization(
  String actorId,
  String action, {
  String resource = 'user',
}) => AuthAdminMutationAuthorization(
  actorId: actorId,
  administratorRoles: const <String>{'admin'},
  administratorUserIds: const <String>{},
  rolePermissions: const <String, AuthAdminPermissionSet>{
    'admin': <String, Iterable<String>>{
      'user': <String>['update', 'set-role', 'set-password'],
      'session': <String>['revoke'],
    },
  },
  requirements: <AuthAdminPermissionRequirement>[
    AuthAdminPermissionRequirement(resource, action),
  ],
);

AuthUser _user(String id, {String role = 'user'}) =>
    AuthUser(id: id, email: '$id@example.test', roles: <String>[role]);

Future<void> _seed(AuthStore store, AuthUser user) async {
  final now = DateTime.utc(2030);
  final created = await store.credentials.register(
    user,
    AuthPasswordCredential(
      id: 'credential-${user.id}',
      userId: user.id,
      identifier: user.email!,
      passwordHash: 'encoded-initial',
      createdAt: now,
      updatedAt: now,
    ),
  );
  _check(created != null, 'fixture could not seed ${user.id}');
}

Future<void> _expectFlow(
  FutureOr<Object?> Function() operation,
  String code,
) async {
  try {
    await Future.sync(operation);
  } on AuthFlowException catch (error) {
    _check(error.code == code, 'expected $code, received ${error.code}');
    return;
  }
  _check(false, 'expected AuthFlowException($code)');
}

Future<String?> _captureFlow(FutureOr<Object?> Function() operation) async {
  try {
    await Future.sync(operation);
    return null;
  } on AuthFlowException catch (error) {
    return error.code;
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
