import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  test(
    'generated concurrent admin sequences never resurrect deleted users',
    () async {
      final runner = PropertyTestRunner<int>(Gen.integer(min: 0, max: 255), (
        shape,
      ) async {
        final core = InMemoryAuthStore();
        final administrator = _user('admin-$shape', admin: true);
        final target = _user('target-$shape');
        await _seed(core, administrator);
        await _seed(core, target);
        await core.sessions.create(_session(target.id, shape));
        final plugin = AdminPlugin<Object>(store: InMemoryAuthAdminStore(core));
        _runtime(core, plugin);

        final candidates = <Future<Object?> Function()>[
          () => _capture(
            () => _invoke(
              plugin,
              'admin.disableUser',
              administrator,
              <String, dynamic>{
                'userId': target.id,
                'reason': 'generated-$shape',
              },
            ),
          ),
          () => _capture(
            () => _invoke(
              plugin,
              'admin.updateUser',
              administrator,
              <String, dynamic>{
                'userId': target.id,
                'name': 'generated-$shape',
              },
            ),
          ),
          () => _capture(
            () => _invoke(
              plugin,
              shape.isEven ? 'admin.banUser' : 'admin.unbanUser',
              administrator,
              <String, dynamic>{'userId': target.id},
            ),
          ),
          () => _capture(
            () => _invoke(
              plugin,
              'admin.revokeUserSessions',
              administrator,
              <String, dynamic>{'userId': target.id},
            ),
          ),
          () => _capture(
            () => _invoke(
              plugin,
              'admin.removeUser',
              administrator,
              <String, dynamic>{'userId': target.id},
            ),
          ),
        ];
        final order = shape.isEven ? candidates : candidates.reversed.toList();
        await Future.wait(<Future<Object?>>[
          for (final operation in order) operation(),
        ]);

        expect(await core.users.findById(target.id), isNull);
        expect(await core.credentials.findByIdentifier(target.email!), isNull);
        expect(await core.sessions.listForUser(target.id), isEmpty);
      }, PropertyConfig(numTests: 128, seed: 20260820));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );

  test(
    'generated credential values stay out of failures and serialization',
    () async {
      final core = InMemoryAuthStore();
      final administrator = _user('admin-secret', admin: true);
      final target = _user('target-secret');
      await _seed(core, administrator);
      await _seed(core, target);
      final plugin = AdminPlugin<Object>(
        store: InMemoryAuthAdminStore(
          core,
          faultInjector: (point, mutation) {
            if (mutation is AuthAdminSetPasswordMutation) {
              throw StateError('admin mutation failed');
            }
          },
        ),
      );
      _runtime(core, plugin);
      final runner = PropertyTestRunner<int>(
        Gen.integer(min: -0x7fffffff, max: 0x7fffffff),
        (value) async {
          final secret = 'credential-$value-${'x' * 24}';
          Object? failure;
          try {
            await _invoke(
              plugin,
              'admin.setUserPassword',
              administrator,
              <String, dynamic>{'userId': target.id, 'newPassword': secret},
            );
          } catch (error) {
            failure = error;
          }
          expect(failure, isA<StateError>());
          expect(failure.toString(), isNot(contains(secret)));
          expect(plugin.toString(), isNot(contains(secret)));
          expect(
            (await core.credentials.findByIdentifier(
              target.email!,
            ))?.passwordHash,
            'hash:initial-password',
          );
          expect(await plugin.store.listAuditRecords(), isEmpty);
        },
        PropertyConfig(numTests: 300, seed: 20260821),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );
}

String _report(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: ${result.error}; '
    'input=${result.failingInput}; seed=${result.seed}';

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
  Map<String, dynamic> input,
) => Future<Object?>.value(
  plugin.endpoints
      .singleWhere((endpoint) => endpoint.id == operation)
      .invoke(
        AuthOperationInvocation<Object>(context: Object(), user: user),
        AuthEndpointRequest(body: input),
      ),
);

Future<Object?> _capture(Future<Object?> Function() operation) async {
  try {
    return await operation();
  } on AuthFlowException catch (error) {
    return error.code;
  }
}

AuthUser _user(String id, {bool admin = false}) => AuthUser(
  id: id,
  email: '$id@example.test',
  roles: <String>[if (admin) 'admin' else 'user'],
);

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

AuthSessionRecord _session(String userId, int shape) {
  final now = DateTime.utc(2026, 8, 20);
  return AuthSessionRecord(
    id: 'session-$shape',
    tokenHash: 'hash-session-$shape',
    userId: userId,
    createdAt: now,
    expiresAt: now.add(const Duration(days: 1)),
    lastUsedAt: now,
    authenticationMethod: 'credentials',
  );
}

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
