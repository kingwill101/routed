import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('Admin atomic mutations', () {
    test(
      'revalidates custom-role permissions inside the store boundary',
      () async {
        final core = InMemoryAuthStore();
        final administrator = AuthUser(
          id: 'support-1',
          email: 'support@example.test',
          roles: const <String>['support'],
        );
        final target = AuthUser(
          id: 'user-1',
          email: 'user@example.test',
          roles: const <String>['user'],
        );
        await _seed(core, administrator);
        await _seed(core, target);
        final plugin = AdminPlugin<Object>(
          store: InMemoryAuthAdminStore(core),
          options: const AuthAdminOptions<Object>(
            adminRoles: <String>{'admin', 'support'},
            roles: <String, AuthAdminPermissionSet>{
              'support': <String, Iterable<String>>{
                'user': <String>['update'],
              },
            },
          ),
        );
        _runtime(core, plugin);

        await core.updateUserForAdministration(
          AuthUser(
            id: administrator.id,
            email: administrator.email,
            roles: const <String>['user'],
          ),
        );

        await expectLater(
          _invoke(plugin, 'admin.updateUser', administrator, <String, dynamic>{
            'userId': target.id,
            'name': 'must not commit',
          }),
          _flow('admin_forbidden'),
        );
        expect((await core.users.findById(target.id))?.name, isNull);
        expect(
          (await core.users.findById(administrator.id))?.roles,
          const <String>['user'],
        );
      },
    );

    test(
      'rolls credential, session, and JWT state back on a store fault',
      () async {
        final core = InMemoryAuthStore();
        final administrator = _admin();
        final target = _member();
        await _seed(core, administrator);
        await _seed(core, target);
        await core.sessions.create(_session(target.id, 'target-session'));
        final beforeVersion = await core.jwtVersions.current(target.id);
        final store = InMemoryAuthAdminStore(
          core,
          faultInjector: (point, mutation) {
            if (mutation is AuthAdminSetPasswordMutation) {
              throw StateError('injected admin persistence fault');
            }
          },
        );
        final plugin = AdminPlugin<Object>(store: store);
        _runtime(core, plugin);

        await expectLater(
          _invoke(
            plugin,
            'admin.setUserPassword',
            administrator,
            <String, dynamic>{
              'userId': target.id,
              'newPassword': 'replacement-password',
            },
          ),
          throwsA(isA<StateError>()),
        );

        final credential = await core.credentials.findByIdentifier(
          target.email!,
        );
        expect(credential?.passwordHash, 'hash:initial-password');
        expect(
          (await core.sessions.listForUser(target.id)).single.isActive(),
          isTrue,
        );
        expect(await core.jwtVersions.current(target.id), beforeVersion);
        expect(await store.listAuditRecords(), isEmpty);
      },
    );

    test('serializes concurrent update, disable, and hard deletion', () async {
      for (var iteration = 0; iteration < 24; iteration++) {
        final core = InMemoryAuthStore();
        final administrator = _admin();
        final target = _member();
        await _seed(core, administrator);
        await _seed(core, target);
        await core.sessions.create(_session(target.id, 'session-$iteration'));
        final plugin = AdminPlugin<Object>(store: InMemoryAuthAdminStore(core));
        _runtime(core, plugin);

        final operations = <Future<Object?>>[
          _capture(
            () => _invoke(
              plugin,
              'admin.updateUser',
              administrator,
              <String, dynamic>{
                'userId': target.id,
                'name': 'updated-$iteration',
              },
            ),
          ),
          _capture(
            () => _invoke(
              plugin,
              'admin.disableUser',
              administrator,
              <String, dynamic>{'userId': target.id, 'reason': 'security'},
            ),
          ),
          _capture(
            () => _invoke(
              plugin,
              'admin.removeUser',
              administrator,
              <String, dynamic>{'userId': target.id},
            ),
          ),
        ];
        if (iteration.isOdd) operations.setAll(0, operations.reversed);
        await Future.wait(operations);

        expect(await core.users.findById(target.id), isNull);
        expect(await core.credentials.findByIdentifier(target.email!), isNull);
        expect(await core.sessions.listForUser(target.id), isEmpty);
      }
    });

    test(
      'uses server sessions as single-use impersonation transitions',
      () async {
        final core = InMemoryAuthStore();
        final administrator = _admin();
        final target = _member();
        await _seed(core, administrator);
        await _seed(core, target);
        await core.sessions.create(_session(administrator.id, 'admin-session'));
        final plugin = AdminPlugin<Object>(store: InMemoryAuthAdminStore(core));
        _runtime(core, plugin);
        final startControl = _SessionControl('admin-session');

        final first = await _invoke(
          plugin,
          'admin.impersonateUser',
          administrator,
          <String, dynamic>{'userId': target.id},
          control: startControl,
        );
        expect(first, isA<AuthEndpointAuthenticationIntent>());
        expect(
          (await core.sessions.listForUser(administrator.id)).single.isActive(),
          isFalse,
        );
        await expectLater(
          _invoke(
            plugin,
            'admin.impersonateUser',
            administrator,
            <String, dynamic>{'userId': target.id},
            control: startControl,
          ),
          _flow('session_not_found'),
        );

        await core.sessions.create(
          _session(
            target.id,
            'impersonated-session',
            impersonatedBy: administrator.id,
          ),
        );
        final stopControl = _SessionControl('impersonated-session');
        final stopped = await _invoke(
          plugin,
          'admin.stopImpersonating',
          target,
          const <String, dynamic>{},
          control: stopControl,
        );
        expect(stopped, isA<AuthEndpointAuthenticationIntent>());
        await expectLater(
          _invoke(
            plugin,
            'admin.stopImpersonating',
            target,
            const <String, dynamic>{},
            control: stopControl,
          ),
          _flow('not_impersonating'),
        );
      },
    );

    test(
      'distinguishes one-session revocation from global JWT revocation',
      () async {
        final core = InMemoryAuthStore();
        final administrator = _admin();
        final target = _member();
        await _seed(core, administrator);
        await _seed(core, target);
        await core.sessions.create(_session(target.id, 'first-session'));
        await core.sessions.create(_session(target.id, 'second-session'));
        final plugin = AdminPlugin<Object>(store: InMemoryAuthAdminStore(core));
        _runtime(core, plugin);
        final initialVersion = await core.jwtVersions.current(target.id);

        await _invoke(
          plugin,
          'admin.revokeUserSession',
          administrator,
          <String, dynamic>{'userId': target.id, 'sessionId': 'first-session'},
        );
        expect(await core.jwtVersions.current(target.id), initialVersion);

        await _invoke(
          plugin,
          'admin.revokeUserSessions',
          administrator,
          <String, dynamic>{'userId': target.id},
        );
        expect(await core.jwtVersions.current(target.id), initialVersion + 1);
        expect(
          (await core.sessions.listForUser(
            target.id,
          )).every((session) => !session.isActive()),
          isTrue,
        );

        final revokeAll = plugin.endpoints.singleWhere(
          (endpoint) => endpoint.id == 'admin.revokeUserSessions',
        );
        final semantics = revokeAll.semantics as AuthMutationOperationSemantics;
        expect(semantics.persistence.atomicity, AuthMutationAtomicity.atomic);
        expect(
          semantics.persistence.reference?.atomicOperationId,
          'revokeUserAccess',
        );
        final audit = (await plugin.store.listAuditRecords(
          targetUserId: target.id,
        )).last;
        expect(audit.operation, 'admin.revokeUserSessions');
        expect(audit.initiatorUserId, administrator.id);
        expect(audit.toJson().toString(), isNot(contains('session-')));
      },
    );
  });
}

AuthRuntime<Object> _runtime(
  InMemoryAuthStore core,
  AdminPlugin<Object> plugin,
) => AuthRuntime<Object>(
  options: AuthOptions<Object>(
    providers: const <AuthProvider>[],
    store: core,
    storeMode: AuthStoreMode.ephemeral,
    passwordHasher: const _Hasher(),
    plugins: <AuthServerPlugin<Object>>[plugin],
  ),
);

Future<Object?> _invoke(
  AdminPlugin<Object> plugin,
  String operation,
  AuthUser user,
  Map<String, dynamic> input, {
  AuthServerPluginSessionControl? control,
}) => Future<Object?>.value(
  plugin.endpoints
      .singleWhere((endpoint) => endpoint.id == operation)
      .invoke(
        AuthOperationInvocation<Object>(
          context: Object(),
          user: user,
          sessionControl: control,
        ),
        input,
      ),
);

Future<Object?> _capture(Future<Object?> Function() operation) async {
  try {
    return await operation();
  } on AuthFlowException catch (error) {
    return error.code;
  }
}

Future<void> _seed(InMemoryAuthStore core, AuthUser user) async {
  final now = DateTime.utc(2026, 8, 20);
  final created = await core.credentials.register(
    user,
    AuthPasswordCredential(
      id: 'credential-${user.id}',
      userId: user.id,
      identifier: user.email!,
      passwordHash: 'hash:initial-password',
      createdAt: now,
      updatedAt: now,
    ),
  );
  expect(created, isNotNull);
}

AuthUser _admin() => AuthUser(
  id: 'admin-1',
  email: 'admin@example.test',
  roles: <String>['admin'],
);

AuthUser _member() =>
    AuthUser(id: 'user-1', email: 'user@example.test', roles: <String>['user']);

AuthSessionRecord _session(String userId, String id, {String? impersonatedBy}) {
  final now = DateTime.utc(2026, 8, 20);
  return AuthSessionRecord(
    id: id,
    tokenHash: 'hash-$id',
    userId: userId,
    createdAt: now,
    expiresAt: now.add(const Duration(days: 1)),
    lastUsedAt: now,
    authenticationMethod: impersonatedBy == null
        ? 'credentials'
        : 'impersonation',
    impersonatedBy: impersonatedBy,
  );
}

Matcher _flow(String code) => throwsA(
  isA<AuthFlowException>().having((error) => error.code, 'code', code),
);

final class _Hasher implements PasswordHasher {
  const _Hasher();

  @override
  String hash(String password) => 'hash:$password';

  @override
  PasswordVerification verify(String password, String encodedHash) =>
      PasswordVerification(
        matches: encodedHash == 'hash:$password',
        needsRehash: false,
      );
}

final class _SessionControl implements AuthServerPluginSessionControl {
  _SessionControl(this.currentSessionId);

  @override
  final AuthSessionStrategy strategy = AuthSessionStrategy.session;

  @override
  String? currentSessionId;

  @override
  Future<void> signOut() async {}
}
