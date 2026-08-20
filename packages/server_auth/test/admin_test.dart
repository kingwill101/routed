import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('AdminPlugin', () {
    late InMemoryAuthStore core;
    late InMemoryAuthAdminStore adminStore;
    late AdminPlugin<Object> feature;
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
      feature = AdminPlugin<Object>(store: adminStore);
      AuthRuntime<Object>(
        options: AuthOptions(
          providers: const [],
          store: core,
          storeMode: AuthStoreMode.ephemeral,
          passwordHasher: const _Hasher(),
          plugins: [feature],
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
      expect(without.plugin(authAdminPluginId), isNull);

      final runtime = AuthRuntime<Object>(
        options: AuthOptions(
          providers: const [],
          store: core,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [feature],
        ),
      );
      expect(runtime.registry.endpoints, hasLength(20));
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
      'custom administrator roles retain their restricted permissions',
      () async {
        final supervisor = AuthUser(
          id: 'support-1',
          email: 'support@example.com',
          roles: const ['support-supervisor'],
        );
        await _seed(core, supervisor);
        final restricted = AdminPlugin<Object>(
          store: adminStore,
          options: const AuthAdminOptions(
            adminRoles: {'admin', 'support-supervisor'},
            roles: {
              'support-supervisor': {
                'user': ['get'],
              },
            },
          ),
        );
        AuthRuntime<Object>(
          options: AuthOptions(
            providers: const [],
            store: core,
            storeMode: AuthStoreMode.ephemeral,
            plugins: [restricted],
          ),
        );

        expect(
          await restricted.hasPermission(supervisor.id, 'user', 'get'),
          isTrue,
        );
        expect(
          await restricted.hasPermission(supervisor.id, 'user', 'delete'),
          isFalse,
        );
        await expectLater(
          _invoke(restricted, 'admin.removeUser', supervisor, {
            'userId': member.id,
          }),
          _flow('admin_forbidden'),
        );
        expect(await core.users.findById(member.id), member);
      },
    );

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

    test('tombstones users before retention purge', () async {
      final deletedAt = DateTime.utc(2026, 8, 19, 12);
      final tombstoned = await core.tombstoneUserForAdministration(
        member.id,
        deletedAt: deletedAt,
      );
      expect(tombstoned, isTrue);
      final retained = await core.users.findById(member.id);
      expect(retained, isNotNull);
      expect(retained?.email, isNull);
      expect(retained?.attributes['deletedAt'], deletedAt.toIso8601String());
      expect(await core.users.findByEmail(member.email!), isNull);
      expect(await core.credentials.findByIdentifier(member.email!), isNull);
      expect(
        await core.purgeTombstonedUserForAdministration(member.id),
        isTrue,
      );
      expect(await core.users.findById(member.id), isNull);
    });

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

    test('ban and disable revoke composed API-key credentials', () async {
      var keyId = 0;
      var secretId = 0;
      final apiKeys = AuthApiKeyPlugin<Object>(
        store: InMemoryAuthApiKeyStore(),
        keyIdGenerator: ({int length = 32}) => 'key-${keyId++}',
        secretGenerator: ({int length = 32}) => 'secret-${secretId++}',
      );
      feature = AdminPlugin<Object>(store: adminStore);
      AuthRuntime<Object>(
        options: AuthOptions(
          providers: const [],
          store: core,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [apiKeys, feature],
        ),
      );

      final bannedKey = await apiKeys.issue(
        userId: member.id,
        name: 'before-ban',
      );
      await _invoke(feature, 'admin.banUser', admin, {'userId': member.id});
      expect(await apiKeys.authenticate(bannedKey.key), isNull);

      await _invoke(feature, 'admin.unbanUser', admin, {'userId': member.id});
      final disabledKey = await apiKeys.issue(
        userId: member.id,
        name: 'before-disable',
      );
      await _invoke(feature, 'admin.disableUser', admin, {'userId': member.id});
      expect(await apiKeys.authenticate(disabledKey.key), isNull);
    });

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
        feature = AdminPlugin<Object>(
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
            plugins: [feature],
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
        final guarded = AdminPlugin<Object>(
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
            plugins: [guarded],
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

    test('hard deletion cascades into API-key and WebAuthn data', () async {
      final apiKeyStore = InMemoryAuthApiKeyStore();
      final apiKeys = AuthApiKeyPlugin<Object>(
        store: apiKeyStore,
        keyIdGenerator: ({length = 32}) => 'member-key',
        secretGenerator: ({length = 32}) => 'member-secret',
      );
      final webAuthn = WebAuthnPlugin<Object>(
        provider: WebAuthnProvider(
          getUserInfo: (_, _, _) => null,
          getRelyingParty: (_, _) => const WebAuthnRelyingParty(
            id: 'example.com',
            name: 'Example',
            origin: 'https://example.com',
          ),
        ),
      );
      feature = AdminPlugin<Object>(store: adminStore);
      AuthRuntime<Object>(
        options: AuthOptions(
          providers: const [],
          store: core,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [apiKeys, webAuthn, feature],
        ),
      );
      final issued = await apiKeys.issue(userId: member.id, name: 'CLI');
      final createdAt = DateTime.now().toUtc();
      await core.webAuthnAuthenticators.create(
        WebAuthnAuthenticator(
          credentialId: 'member-passkey',
          publicKey: 'member-public-key',
          counter: 0,
          userId: member.id,
          createdAt: createdAt,
        ),
      );
      await core.webAuthnChallenges.save(
        AuthWebAuthnChallenge(
          id: 'member-challenge',
          challengeHash: 'member-challenge-hash',
          ceremony: AuthWebAuthnCeremony.registration,
          relyingPartyId: 'example.com',
          origin: 'https://example.com',
          createdAt: createdAt,
          expiresAt: createdAt.add(const Duration(minutes: 5)),
          userId: member.id,
        ),
      );

      await _invoke(feature, 'admin.removeUser', admin, {'userId': member.id});

      expect(await apiKeys.authenticate(issued.key), isNull);
      expect(
        await core.webAuthnAuthenticators.findByCredentialId('member-passkey'),
        isNull,
      );
      expect(
        await core.webAuthnChallenges.consume(
          challengeHash: 'member-challenge-hash',
          ceremony: AuthWebAuthnCeremony.registration,
          relyingPartyId: 'example.com',
          origin: 'https://example.com',
          userId: member.id,
          now: createdAt,
        ),
        isNull,
      );
    });

    test('failed contributor deletion rolls back earlier namespaces', () async {
      final apiKeyStore = InMemoryAuthApiKeyStore();
      final apiKeys = AuthApiKeyPlugin<Object>(
        store: apiKeyStore,
        keyIdGenerator: ({length = 32}) => 'member-key',
        secretGenerator: ({length = 32}) => 'member-secret',
      );
      final failure = _FailingDeletionPlugin();
      feature = AdminPlugin<Object>(store: adminStore);
      AuthRuntime<Object>(
        options: AuthOptions(
          providers: const [],
          store: core,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [apiKeys, failure, feature],
        ),
      );
      final issued = await apiKeys.issue(userId: member.id, name: 'CLI');

      await expectLater(
        _invoke(feature, 'admin.removeUser', admin, {'userId': member.id}),
        throwsA(isA<StateError>()),
      );

      expect(await core.users.findById(member.id), member);
      expect(await apiKeys.authenticate(issued.key), isNotNull);
    });

    test(
      'rejected email conflicts preserve credential lookup indexes',
      () async {
        await expectLater(
          _invoke(feature, 'admin.updateUser', admin, {
            'userId': member.id,
            'email': admin.email,
          }),
          _flow('email_taken'),
        );

        final memberCredential = await core.credentials.findByIdentifier(
          member.email!,
        );
        final adminCredential = await core.credentials.findByIdentifier(
          admin.email!,
        );
        expect(memberCredential?.userId, member.id);
        expect(adminCredential?.userId, admin.id);
        expect(await core.users.findByEmail(member.email!), member);
        expect(await core.users.findByEmail(admin.email!), admin);
      },
    );

    test(
      'impersonation is server-session-only and preserves actor metadata',
      () async {
        final control = _SessionControl();
        final startedIntent =
            await _invokeWithControl(feature, 'admin.impersonateUser', admin, {
                  'userId': member.id,
                }, control)
                as AuthEndpointAuthenticationIntent;
        final started = _map(
          await startedIntent.projectResponse(
            AuthSession(
              user: startedIntent.user,
              expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
              strategy: AuthSessionStrategy.session,
            ).toJson(),
          ),
        );
        expect(_map(started['data'])['user']['id'], member.id);
        expect(startedIntent.impersonatedBy, admin.id);
        expect(startedIntent.authenticationMethod, 'impersonation');

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
        final stoppedIntent =
            await _invokeWithControl(
                  feature,
                  'admin.stopImpersonating',
                  member,
                  const {},
                  control,
                )
                as AuthEndpointAuthenticationIntent;
        final stopped = _map(
          await stoppedIntent.projectResponse(
            AuthSession(
              user: stoppedIntent.user,
              expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
              strategy: AuthSessionStrategy.session,
            ).toJson(),
          ),
        );
        expect(_map(_map(stopped['data'])['session'])['user']['id'], admin.id);
        expect(stoppedIntent.authenticationMethod, 'impersonation-return');

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
        final organizations = OrganizationPlugin<Object>(
          store: organizationStore,
        );
        feature = AdminPlugin<Object>(store: adminStore);
        AuthRuntime<Object>(
          options: AuthOptions(
            providers: const [],
            store: core,
            storeMode: AuthStoreMode.ephemeral,
            plugins: [organizations, feature],
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
  AdminPlugin<Object> feature,
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
  AdminPlugin<Object> feature,
  String id,
  AuthUser user,
  Map<String, dynamic> input,
  AuthServerPluginSessionControl control,
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

final class _FailingDeletionPlugin
    implements
        AuthServerPlugin<Object>,
        AuthReversibleUserDataDeletionContributor {
  @override
  String get id => 'failing-deletion';

  @override
  String get userDataNamespace => 'failing-deletion';

  @override
  void configure(AuthServerPluginContext<Object> context) {}

  @override
  void validateUserDeletion(String userId) {}

  @override
  AuthUserDataDeletionCheckpoint checkpointUserData(String userId) =>
      AuthUserDataDeletionCheckpoint.capture(const []);

  @override
  void deleteUserData(String userId) {
    throw StateError('simulated deletion failure');
  }
}

final class _SessionControl implements AuthServerPluginSessionControl {
  _SessionControl({this.strategy = AuthSessionStrategy.session});

  @override
  final AuthSessionStrategy strategy;
  @override
  String? currentSessionId;
  bool signedOut = false;

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}
