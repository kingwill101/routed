import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('AdminFeature', () {
    late InMemoryAuthStore core;
    late InMemoryAuthAdminStore adminStore;
    late AdminFeature<Object> feature;
    late AuthUser admin;
    late AuthUser member;

    setUp(() async {
      core = InMemoryAuthStore();
      adminStore = InMemoryAuthAdminStore(core);
      admin = AuthUser(
        id: 'admin-1',
        email: 'admin@example.com',
        name: 'Admin',
        roles: const ['admin'],
      );
      member = AuthUser(
        id: 'user-1',
        email: 'user@example.com',
        name: 'User',
        roles: const ['user'],
      );
      await _seed(core, admin);
      await _seed(core, member);
      feature = AdminFeature<Object>(store: adminStore);
      AuthRuntime<Object>(
        options: AuthOptions(
          providers: const [],
          store: core,
          storeMode: AuthStoreMode.ephemeral,
          passwordHasher: const _Hasher(),
          features: [feature],
        ),
      );
    });

    test('is opt-in and contributes the complete public topology', () {
      final without = AuthRuntime<Object>(
        options: AuthOptions(
          providers: const [],
          store: InMemoryAuthStore(),
          storeMode: AuthStoreMode.ephemeral,
        ),
      );
      expect(without.feature(authAdminFeatureId), isNull);

      final runtime = AuthRuntime<Object>(
        options: AuthOptions(
          providers: const [],
          store: core,
          storeMode: AuthStoreMode.ephemeral,
          features: [feature],
        ),
      );
      expect(runtime.registry.endpoints, hasLength(15));
      expect(
        runtime.registry.endpoints.map((endpoint) => endpoint.path),
        containsAll([
          '/admin/create-user',
          '/admin/ban-user',
          '/admin/impersonate-user',
          '/admin/stop-impersonating',
        ]),
      );
      expect(runtime.registry.persistenceSchemas.single.id, 'admin');
      expect(
        feature.endpoints.every(
          (endpoint) =>
              endpoint.authentication == AuthOperationAuthentication.session,
        ),
        isTrue,
      );
    });

    test(
      'creates, lists, filters, and updates users without exposing secrets',
      () async {
        final created = await _invoke(feature, 'admin.createUser', admin, {
          'email': ' NEW@Example.com ',
          'name': 'New User',
          'password': 'long-enough-password',
          'attributes': {'token': 'secret', 'locale': 'en'},
        });
        final data = _map(_map(created)['data']);
        expect(data['email'], 'new@example.com');
        expect(_map(data['attributes']), {'locale': 'en'});
        expect(created.toString(), isNot(contains('long-enough-password')));
        expect(created.toString(), isNot(contains('secret')));

        final listed = _map(
          await _invoke(feature, 'admin.listUsers', admin, {
            'search': 'new',
            'role': 'user',
            'limit': 500,
          }),
        );
        expect(listed['total'], 1);
        expect(listed['limit'], 100);

        await _invoke(feature, 'admin.updateUser', admin, {
          'userId': data['id'],
          'email': 'changed@example.com',
          'name': 'Changed',
        });
        expect(await core.users.findByEmail('changed@example.com'), isNotNull);
        expect(await core.users.findByEmail('new@example.com'), isNull);
        expect(
          await core.credentials.findByIdentifier('changed@example.com'),
          isNotNull,
        );
        expect(
          await core.credentials.findByIdentifier('new@example.com'),
          isNull,
        );
      },
    );

    test(
      'sensitive mutations revoke sessions and rotate JWT versions',
      () async {
        await core.sessions.create(_session(member.id));
        final before = await core.jwtVersions.current(member.id);
        await _invoke(feature, 'admin.setRole', admin, {
          'userId': member.id,
          'roles': ['editor'],
        });
        expect(
          (await core.sessions.listForUser(member.id)).single.isActive(),
          isFalse,
        );
        expect(await core.jwtVersions.current(member.id), before + 1);

        await _invoke(feature, 'admin.setUserPassword', admin, {
          'userId': member.id,
          'newPassword': 'replacement-password',
        });
        final credential = await core.credentials.findByIdentifier(
          member.email!,
        );
        expect(credential!.passwordHash, 'hash:replacement-password');
        expect(credential.passwordHash, isNot('replacement-password'));
      },
    );

    test(
      'ban policy blocks sign-in and session resolution then expires',
      () async {
        await _invoke(feature, 'admin.banUser', admin, {
          'userId': member.id,
          'banReason': 'abuse',
          'banExpiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        });
        await expectLater(
          feature.enforceAuthenticationPolicy(
            AuthAuthenticationPolicyRequest(
              context: Object(),
              user: member,
              phase: AuthAuthenticationPolicyPhase.beforeSessionIssue,
            ),
          ),
          _flow('account_unavailable'),
        );
        await _invoke(feature, 'admin.unbanUser', admin, {'userId': member.id});
        await feature.enforceAuthenticationPolicy(
          AuthAuthenticationPolicyRequest(
            context: Object(),
            user: member,
            phase: AuthAuthenticationPolicyPhase.resolveSession,
          ),
        );
      },
    );

    test(
      'blocks dangerous self actions and preserves the last administrator',
      () async {
        await expectLater(
          _invoke(feature, 'admin.banUser', admin, {'userId': admin.id}),
          _flow('self_ban'),
        );
        await expectLater(
          _invoke(feature, 'admin.removeUser', admin, {'userId': admin.id}),
          _flow('self_delete'),
        );
        await expectLater(
          _invoke(feature, 'admin.setRole', admin, {
            'userId': admin.id,
            'roles': ['user'],
          }),
          _flow('self_admin_removal'),
        );
        await expectLater(
          adminStore.replaceRoles(
            admin.id,
            const ['user'],
            administratorRoles: const {'admin'},
            administratorUserIds: const {},
          ),
          _flow('last_admin'),
        );
      },
    );

    test(
      'after-commit failures become warnings and events are redacted',
      () async {
        final events = <AuthAdminLifecycleEvent>[];
        feature = AdminFeature<Object>(
          store: adminStore,
          options: AuthAdminOptions(
            hooks: AuthAdminHooks(
              afterUser: (_) => throw StateError('hook secret'),
            ),
            emitEvent: events.add,
          ),
        );
        AuthRuntime<Object>(
          options: AuthOptions(
            providers: const [],
            store: core,
            storeMode: AuthStoreMode.ephemeral,
            passwordHasher: const _Hasher(),
            features: [feature],
          ),
        );
        final response = _map(
          await _invoke(feature, 'admin.createUser', admin, {
            'email': 'warn@example.com',
            'name': 'Warn',
            'password': 'long-enough-password',
          }),
        );
        expect(
          _mapList(response['warnings']).single['code'],
          'after_hook_failed',
        );
        expect(await core.users.findByEmail('warn@example.com'), isNotNull);
        expect(events.single.toJson().toString(), isNot(contains('password')));
      },
    );

    test(
      'hard deletion removes core user data and honors deletion guards',
      () async {
        await core.sessions.create(_session(member.id));
        await core.accounts.link(
          AuthAccount(
            providerId: 'github',
            providerAccountId: 'provider-user',
            userId: member.id,
          ),
        );
        final guarded = AdminFeature<Object>(
          store: adminStore,
          options: AuthAdminOptions(
            validateDeletion: (_) => throw AuthFlowException('last_owner'),
          ),
        );
        AuthRuntime<Object>(
          options: AuthOptions(
            providers: const [],
            store: core,
            storeMode: AuthStoreMode.ephemeral,
            features: [guarded],
          ),
        );
        await expectLater(
          _invoke(guarded, 'admin.removeUser', admin, {'userId': member.id}),
          _flow('last_owner'),
        );
        expect(await core.users.findById(member.id), isNotNull);

        final response = _map(
          await _invoke(feature, 'admin.removeUser', admin, {
            'userId': member.id,
          }),
        );
        expect(response['data'], isTrue);
        expect(await core.users.findById(member.id), isNull);
        expect(await core.credentials.findByIdentifier(member.email!), isNull);
        expect(await core.sessions.listForUser(member.id), isEmpty);
        expect(await core.accounts.find('github', 'provider-user'), isNull);
      },
    );

    test(
      'impersonation is server-session-only and preserves actor metadata',
      () async {
        final control = _SessionControl();
        final started = _map(
          await _invokeWithControl(feature, 'admin.impersonateUser', admin, {
            'userId': member.id,
          }, control),
        );
        expect(_map(started['data'])['user']['id'], member.id);
        expect(control.impersonatedBy, admin.id);
        expect(control.authenticationMethod, 'impersonation');

        final now = DateTime.now().toUtc();
        await core.sessions.create(
          AuthSessionRecord(
            id: 'impersonated-session',
            tokenHash: 'impersonated-hash',
            userId: member.id,
            createdAt: now,
            expiresAt: now.add(const Duration(hours: 1)),
            lastUsedAt: now,
            authenticationMethod: 'impersonation',
            impersonatedBy: admin.id,
          ),
        );
        control.currentSessionId = 'impersonated-session';
        final stopped = _map(
          await _invokeWithControl(
            feature,
            'admin.stopImpersonating',
            member,
            const {},
            control,
          ),
        );
        expect(_map(_map(stopped['data'])['session'])['user']['id'], admin.id);
        expect(control.authenticationMethod, 'impersonation-return');

        final jwt = _SessionControl(strategy: AuthSessionStrategy.jwt);
        await expectLater(
          _invokeWithControl(feature, 'admin.impersonateUser', admin, {
            'userId': member.id,
          }, jwt),
          _flow('impersonation_requires_server_session'),
        );
      },
    );

    test(
      'composed organization data rejects last-owner deletion and cascades',
      () async {
        final organizationStore = InMemoryAuthOrganizationStore();
        final organizations = OrganizationFeature<Object>(
          store: organizationStore,
        );
        feature = AdminFeature<Object>(store: adminStore);
        AuthRuntime<Object>(
          options: AuthOptions(
            providers: const [],
            store: core,
            storeMode: AuthStoreMode.ephemeral,
            features: [organizations, feature],
          ),
        );
        final organization = (await organizations.createOrganization(
          context: Object(),
          user: member,
          name: 'Acme',
          slug: 'acme',
        )).data;
        await expectLater(
          _invoke(feature, 'admin.removeUser', admin, {'userId': member.id}),
          _flow('last_owner'),
        );
        await organizations.trustedAddMember(
          context: Object(),
          actor: member,
          organizationId: organization.id,
          userId: admin.id,
          roles: const ['owner'],
        );
        await _invoke(feature, 'admin.removeUser', admin, {
          'userId': member.id,
        });
        expect(
          await organizationStore.findMember(organization.id, member.id),
          isNull,
        );
        expect(await core.users.findById(member.id), isNull);
      },
    );
  });
}

Future<Object?> _invoke(
  AdminFeature<Object> feature,
  String id,
  AuthUser user,
  Map<String, dynamic> input,
) {
  final endpoint = feature.endpoints.singleWhere((value) => value.id == id);
  return Future<Object?>.value(
    endpoint.invoke(
      AuthOperationInvocation(context: Object(), user: user),
      input,
    ),
  );
}

Future<Object?> _invokeWithControl(
  AdminFeature<Object> feature,
  String id,
  AuthUser user,
  Map<String, dynamic> input,
  AuthFeatureSessionControl control,
) {
  final endpoint = feature.endpoints.singleWhere((value) => value.id == id);
  return Future<Object?>.value(
    endpoint.invoke(
      AuthOperationInvocation(
        context: Object(),
        user: user,
        sessionControl: control,
      ),
      input,
    ),
  );
}

Future<void> _seed(InMemoryAuthStore store, AuthUser user) async {
  final now = DateTime.now().toUtc();
  final result = await store.credentials.register(
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
  expect(result, isNotNull);
}

AuthSessionRecord _session(String userId) {
  final now = DateTime.now().toUtc();
  return AuthSessionRecord(
    id: 'session-$userId',
    tokenHash: 'hash-$userId',
    userId: userId,
    createdAt: now,
    expiresAt: now.add(const Duration(hours: 1)),
    lastUsedAt: now,
    authenticationMethod: 'credentials',
  );
}

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value! as Map);

List<Map<String, dynamic>> _mapList(Object? value) =>
    (value! as List).map((item) => _map(item)).toList();

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

final class _SessionControl implements AuthFeatureSessionControl {
  _SessionControl({this.strategy = AuthSessionStrategy.session});

  @override
  final AuthSessionStrategy strategy;
  @override
  String? currentSessionId;
  String? authenticationMethod;
  String? impersonatedBy;
  bool signedOut = false;

  @override
  Future<AuthSession> replaceIdentity(
    AuthUser user, {
    required String authenticationMethod,
    Duration? maximumAge,
    String? impersonatedBy,
  }) async {
    this.authenticationMethod = authenticationMethod;
    this.impersonatedBy = impersonatedBy;
    return AuthSession(
      user: user,
      expiresAt: DateTime.now().toUtc().add(
        maximumAge ?? const Duration(hours: 1),
      ),
      strategy: strategy,
    );
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}
