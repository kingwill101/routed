import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

const _hashKey = '0123456789abcdef0123456789abcdef';

void main() {
  test('composes every built-in and future plugin method type', () async {
    final store = InMemoryAuthStore();
    final phoneStore = InMemoryAuthPhoneNumberStore();
    final apiKeyStore = InMemoryAuthApiKeyStore();
    final webAuthn = _webAuthnPlugin();
    final phone = PhoneNumberPlugin<Object>(
      store: phoneStore,
      sendCode: (_) {},
      codeHashKey: _hashKey,
    );
    final emailOtp = EmailOtpPlugin<Object>(
      sendCode: (_) {},
      rateLimitHashKey: _hashKey,
    );
    final username = UsernamePlugin<Object>();
    final apiKeys = AuthApiKeyPlugin<Object>(
      store: apiKeyStore,
      countsAsPrimaryAuthenticationMethod: true,
      keyIdGenerator: ({int length = 32}) => 'api-key-id',
      secretGenerator: ({int length = 32}) => 'api-key-secret',
    );
    final futureMethod = _FutureMethodPlugin(
      AuthAuthenticationMethod.plugin(
        namespace: 'hardware_recovery',
        id: 'device-1',
      ),
    );
    final runtime = AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: <AuthProvider>[
          CredentialsProvider(),
          _oauthProvider('github'),
          EmailProvider(sendVerificationRequest: (_, _, _) {}),
        ],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        plugins: <AuthServerPlugin<Object>>[
          webAuthn,
          phone,
          emailOtp,
          username,
          apiKeys,
          futureMethod,
        ],
      ),
    );
    final now = DateTime.utc(2026, 8, 20);
    await store.users.create(AuthUser(id: 'user-1', email: 'user@example.com'));
    await store.upsertCredentialForAdministration(
      AuthPasswordCredential(
        id: 'password-1',
        userId: 'user-1',
        identifier: 'user@example.com',
        passwordHash: 'hash',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await store.upsertCredentialForAdministration(
      AuthPasswordCredential(
        id: 'username-1',
        userId: 'user-1',
        identifier: 'alice',
        passwordHash: 'hash',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await store.accounts.link(
      AuthAccount(
        providerId: 'github',
        providerAccountId: 'github-1',
        userId: 'user-1',
      ),
    );
    await phoneStore.bindIdentity(
      AuthPhoneNumberIdentity(
        phoneNumber: '+18765551234',
        userId: 'user-1',
        createdAt: now,
        verifiedAt: now,
      ),
    );
    await store.webAuthnAuthenticators.create(
      WebAuthnAuthenticator(
        credentialId: 'passkey-1',
        publicKey: 'AQ',
        counter: 0,
        userId: 'user-1',
        createdAt: now,
      ),
    );
    await apiKeys.issue(userId: 'user-1', name: 'primary', now: now);

    final snapshot = await runtime.authenticationMethods.snapshotForUser(
      'user-1',
    );

    expect(snapshot.isComplete, isTrue);
    expect(
      snapshot.methods.map((method) => method.kind).toSet(),
      containsAll(<AuthAuthenticationMethodKind>{
        AuthAuthenticationMethodKind.password,
        AuthAuthenticationMethodKind.oauthProvider,
        AuthAuthenticationMethodKind.emailLink,
        AuthAuthenticationMethodKind.passkey,
        AuthAuthenticationMethodKind.phone,
        AuthAuthenticationMethodKind.emailOtp,
        AuthAuthenticationMethodKind.username,
        AuthAuthenticationMethodKind.apiKey,
        AuthAuthenticationMethodKind.plugin,
      }),
    );
  });

  test('one username credential is not counted as two fallbacks', () async {
    final store = InMemoryAuthStore();
    final runtime = AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: <AuthProvider>[CredentialsProvider()],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        plugins: <AuthServerPlugin<Object>>[UsernamePlugin<Object>()],
      ),
    );
    await store.users.create(AuthUser(id: 'user-1'));
    final now = DateTime.utc(2026, 8, 20);
    await store.upsertCredentialForAdministration(
      AuthPasswordCredential(
        id: 'username-1',
        userId: 'user-1',
        identifier: 'alice',
        passwordHash: 'hash',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final snapshot = await runtime.authenticationMethods.snapshotForUser(
      'user-1',
    );

    expect(snapshot.isComplete, isTrue);
    expect(snapshot.methods, hasLength(1));
    expect(snapshot.methods.single.identity, 'credential:username-1');
  });

  test('provider removal excludes the exact provider account pair', () async {
    final store = InMemoryAuthStore();
    final runtime = _oauthRuntime(store);
    await store.users.create(AuthUser(id: 'user-1'));
    await store.accounts.link(
      AuthAccount(
        providerId: 'github',
        providerAccountId: 'shared-id',
        userId: 'user-1',
      ),
    );
    await store.accounts.link(
      AuthAccount(
        providerId: 'gitlab',
        providerAccountId: 'shared-id',
        userId: 'user-1',
      ),
    );

    await unlinkProviderAccount(
      store: store,
      authenticationMethods: runtime.authenticationMethods,
      userId: 'user-1',
      providerId: 'github',
      providerAccountId: 'shared-id',
    );

    expect(await store.accounts.find('github', 'shared-id'), isNull);
    expect(await store.accounts.find('gitlab', 'shared-id'), isNotNull);
  });

  test('provider identity encoding cannot alias delimiter-shaped pairs', () {
    final first = AuthAuthenticationMethod.oauthProvider(
      providerId: 'provider:a',
      providerAccountId: 'account',
    );
    final second = AuthAuthenticationMethod.oauthProvider(
      providerId: 'provider',
      providerAccountId: 'a:account',
    );

    expect(first, isNot(second));
    expect(first.identity, isNot(second.identity));
  });

  test(
    'inactive provider links are removable but never count as fallback',
    () async {
      final store = InMemoryAuthStore();
      final runtime = AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: <AuthProvider>[_oauthProvider('github')],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
        ),
      );
      await store.users.create(AuthUser(id: 'user-1'));
      await store.accounts.link(
        AuthAccount(
          providerId: 'github',
          providerAccountId: 'github-1',
          userId: 'user-1',
        ),
      );
      await store.accounts.link(
        AuthAccount(
          providerId: 'retired-provider',
          providerAccountId: 'retired-1',
          userId: 'user-1',
        ),
      );

      await expectLater(
        unlinkProviderAccount(
          store: store,
          authenticationMethods: runtime.authenticationMethods,
          userId: 'user-1',
          providerId: 'github',
          providerAccountId: 'github-1',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'last_authentication_method',
          ),
        ),
      );

      await unlinkProviderAccount(
        store: store,
        authenticationMethods: runtime.authenticationMethods,
        userId: 'user-1',
        providerId: 'retired-provider',
        providerAccountId: 'retired-1',
      );
      expect(await store.accounts.find('github', 'github-1'), isNotNull);
      expect(
        await store.accounts.find('retired-provider', 'retired-1'),
        isNull,
      );
    },
  );

  test('missing target is not reported as the last method', () async {
    final service = AuthAuthenticationMethodService(
      store: InMemoryAuthStore(),
      contributors: [
        _StaticInventory(
          AuthAuthenticationMethod.plugin(namespace: 'test', id: 'fallback'),
        ),
      ],
    )..composeContributors(const []);
    var mutated = false;

    final result = await service.removeIfSafe(
      userId: 'user-1',
      target: AuthAuthenticationMethod.plugin(namespace: 'test', id: 'missing'),
      mutate: () {
        mutated = true;
        return true;
      },
    );

    expect(result, AuthAuthenticationMethodMutationResult.notFound);
    expect(mutated, isFalse);
  });

  test('incomplete future-plugin inventory fails closed', () async {
    final service = AuthAuthenticationMethodService(
      store: InMemoryAuthStore(),
      contributors: const [_UnavailableInventory()],
    )..composeContributors(const []);
    var mutated = false;

    final result = await service.removeIfSafe(
      userId: 'user-1',
      target: AuthAuthenticationMethod.plugin(namespace: 'test', id: 'target'),
      mutate: () {
        mutated = true;
        return true;
      },
    );

    expect(result, AuthAuthenticationMethodMutationResult.atomicityUnavailable);
    expect(mutated, isFalse);
  });

  test('concurrent cross-store removals preserve exactly one method', () async {
    await _verifyConcurrentRemoval(<int>[0, 1, 2]);
  });

  test('property: every removal ordering preserves a fallback', () async {
    final runner = PropertyTestRunner<int>(
      Gen.integer(min: 0, max: 5),
      (permutation) => _verifyConcurrentRemoval(_permutation(permutation)),
      PropertyConfig(numTests: 120, seed: 20260820),
    );
    final result = await runner.run();
    expect(result.success, isTrue, reason: '${result.error}');
  });

  test('stateful property: repeated removals never reach zero', () async {
    final runner = PropertyTestRunner<int>(
      Gen.integer(min: 0, max: 6560),
      _verifyStatefulRemovalSequence,
      PropertyConfig(numTests: 80, seed: 20260821),
    );
    final result = await runner.run();
    expect(result.success, isTrue, reason: '${result.error}');
  });

  test(
    'durable stores without shared mutation atomicity fail closed',
    () async {
      final core = InMemoryAuthStore();
      final store = _NonAtomicAuthStore(core);
      final service = AuthAuthenticationMethodService(
        store: store,
        contributors: <AuthAuthenticationMethodInventoryContributor>[
          _StaticInventory(
            AuthAuthenticationMethod.plugin(namespace: 'test', id: 'fallback'),
          ),
        ],
      )..composeContributors(const []);
      var mutated = false;

      final result = await service.removeIfSafe(
        userId: 'user-1',
        target: AuthAuthenticationMethod.plugin(
          namespace: 'test',
          id: 'target',
        ),
        mutate: () {
          mutated = true;
          return true;
        },
      );

      expect(
        result,
        AuthAuthenticationMethodMutationResult.atomicityUnavailable,
      );
      expect(mutated, isFalse);
    },
  );

  test('sensitive-action policy accepts only explicit fresh proofs', () {
    const policy = AuthAccountPolicy(
      reauthenticationWindow: Duration(minutes: 5),
    );
    final now = DateTime.utc(2026, 8, 20, 12);

    expect(
      policy.allowsSensitiveAction(
        authenticatedAt: now.subtract(const Duration(minutes: 4)),
        now: now,
      ),
      isTrue,
    );
    expect(
      policy.allowsSensitiveAction(
        authenticatedAt: now.subtract(const Duration(minutes: 6)),
        now: now,
      ),
      isFalse,
    );
    expect(
      policy.allowsSensitiveAction(stepUpVerified: true, now: now),
      isTrue,
    );
    expect(
      policy.allowsSensitiveAction(
        authenticatedAt: now.add(const Duration(seconds: 1)),
        now: now,
      ),
      isFalse,
    );
  });
}

Future<void> _verifyConcurrentRemoval(List<int> order) async {
  final fixture = await _removalFixture();
  final outcomes = await Future.wait<Object>([
    for (final index in order) _capture(fixture.operations[index]),
  ]);
  final errors = outcomes.whereType<AuthFlowException>().toList();
  final snapshot = await fixture.runtime.authenticationMethods.snapshotForUser(
    'user-1',
  );

  expect(errors, hasLength(1));
  expect(errors.single.code, 'last_authentication_method');
  expect(snapshot.isComplete, isTrue);
  expect(snapshot.methods, hasLength(1));
}

Future<void> _verifyStatefulRemovalSequence(int encodedActions) async {
  final fixture = await _removalFixture();
  var remainingActions = encodedActions;
  for (var step = 0; step < 8; step++) {
    final action = fixture.operations[remainingActions % 3];
    remainingActions ~/= 3;
    await _capture(action);
    final snapshot = await fixture.runtime.authenticationMethods
        .snapshotForUser('user-1');
    expect(snapshot.isComplete, isTrue);
    expect(snapshot.methods, isNotEmpty);
  }
}

Future<_RemovalFixture> _removalFixture() async {
  final store = InMemoryAuthStore();
  final apiKeyStore = InMemoryAuthApiKeyStore();
  final webAuthn = _webAuthnPlugin();
  var keySequence = 0;
  final apiKeys = AuthApiKeyPlugin<Object>(
    store: apiKeyStore,
    countsAsPrimaryAuthenticationMethod: true,
    keyIdGenerator: ({int length = 32}) => 'key-${keySequence++}',
    secretGenerator: ({int length = 32}) => 'secret-$keySequence',
  );
  final runtime = AuthRuntime<Object>(
    options: AuthOptions<Object>(
      providers: <AuthProvider>[_oauthProvider('github')],
      store: store,
      storeMode: AuthStoreMode.ephemeral,
      plugins: <AuthServerPlugin<Object>>[webAuthn, apiKeys],
    ),
  );
  await store.users.create(AuthUser(id: 'user-1'));
  await store.accounts.link(
    AuthAccount(
      providerId: 'github',
      providerAccountId: 'github-1',
      userId: 'user-1',
    ),
  );
  await store.webAuthnAuthenticators.create(
    WebAuthnAuthenticator(
      credentialId: 'passkey-1',
      publicKey: 'AQ',
      counter: 0,
      userId: 'user-1',
      createdAt: DateTime.utc(2026, 8, 20),
    ),
  );
  final issued = await apiKeys.issue(userId: 'user-1', name: 'primary');
  return _RemovalFixture(runtime, <Future<void> Function()>[
    () async {
      await unlinkProviderAccount(
        store: store,
        authenticationMethods: runtime.authenticationMethods,
        userId: 'user-1',
        providerId: 'github',
        providerAccountId: 'github-1',
      );
    },
    () =>
        webAuthn.deleteCredential(userId: 'user-1', credentialId: 'passkey-1'),
    () async {
      await apiKeys.revoke('user-1', issued.apiKey.id);
    },
  ]);
}

Future<Object> _capture(Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on AuthFlowException catch (error) {
    return error;
  }
}

List<int> _permutation(int value) => const <List<int>>[
  <int>[0, 1, 2],
  <int>[0, 2, 1],
  <int>[1, 0, 2],
  <int>[1, 2, 0],
  <int>[2, 0, 1],
  <int>[2, 1, 0],
][value];

final class _RemovalFixture {
  const _RemovalFixture(this.runtime, this.operations);

  final AuthRuntime<Object> runtime;
  final List<Future<void> Function()> operations;
}

WebAuthnPlugin<Object> _webAuthnPlugin() => WebAuthnPlugin<Object>(
  provider: WebAuthnProvider(
    getUserInfo: (_, _, _) => null,
    getRelyingParty: (_, _) => const WebAuthnRelyingParty(
      id: 'app.test',
      name: 'App',
      origin: 'https://app.test',
    ),
  ),
);

OAuthProvider<Map<String, dynamic>> _oauthProvider(String id) =>
    OAuthProvider<Map<String, dynamic>>(
      id: id,
      name: id,
      clientId: 'client',
      clientSecret: 'secret',
      authorizationEndpoint: Uri.https('$id.test', '/authorize'),
      tokenEndpoint: Uri.https('$id.test', '/token'),
      profile: (_) => AuthUser(id: 'unused'),
      redirectUri: 'https://app.test/auth/callback/$id',
    );

AuthRuntime<Object> _oauthRuntime(InMemoryAuthStore store) =>
    AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: <AuthProvider>[
          _oauthProvider('github'),
          _oauthProvider('gitlab'),
        ],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
      ),
    );

final class _StaticInventory
    implements AuthAuthenticationMethodInventoryContributor {
  const _StaticInventory(this.method);

  final AuthAuthenticationMethod method;

  @override
  String get authenticationMethodNamespace => method.namespace;

  @override
  AuthAuthenticationMethodSnapshot authenticationMethodsForUser(
    String userId,
  ) => AuthAuthenticationMethodSnapshot.complete([method]);
}

final class _UnavailableInventory
    implements AuthAuthenticationMethodInventoryContributor {
  const _UnavailableInventory();

  @override
  String get authenticationMethodNamespace => 'test';

  @override
  AuthAuthenticationMethodSnapshot authenticationMethodsForUser(
    String userId,
  ) => const AuthAuthenticationMethodSnapshot.unavailable();
}

final class _FutureMethodPlugin
    implements
        AuthServerPlugin<Object>,
        AuthAuthenticationMethodInventoryContributor {
  const _FutureMethodPlugin(this.method);

  final AuthAuthenticationMethod method;

  @override
  String get id => 'future_method';

  @override
  String get authenticationMethodNamespace => method.namespace;

  @override
  AuthAuthenticationMethodSnapshot authenticationMethodsForUser(
    String userId,
  ) => AuthAuthenticationMethodSnapshot.complete([method]);

  @override
  void configure(AuthServerPluginContext<Object> context) {}
}

final class _NonAtomicAuthStore implements AuthStore {
  const _NonAtomicAuthStore(this.delegate);

  final AuthStore delegate;

  @override
  AuthAccountStore get accounts => delegate.accounts;
  @override
  AuthCredentialStore get credentials => delegate.credentials;
  @override
  AuthDeviceAuthorizationStore get deviceAuthorizations =>
      delegate.deviceAuthorizations;
  @override
  AuthEmailChangeTokenStore get emailChangeTokens => delegate.emailChangeTokens;
  @override
  AuthEmailOtpStore get emailOtps => delegate.emailOtps;
  @override
  AuthJwtVersionStore get jwtVersions => delegate.jwtVersions;
  @override
  AuthOAuthChallengeStore get oauthChallenges => delegate.oauthChallenges;
  @override
  AuthPasswordResetTokenStore get passwordResetTokens =>
      delegate.passwordResetTokens;
  @override
  AuthSessionStore get sessions => delegate.sessions;
  @override
  AuthUserStore get users => delegate.users;
  @override
  AuthVerificationTokenStore get verificationTokens =>
      delegate.verificationTokens;
}
