import 'package:property_testing/property_testing.dart';
import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cloudflare_d1.dart';

void main() {
  group('Cloudflare D1 WebAuthn persistence', () {
    final suite = AuthWebAuthnStoreConformanceSuite(() async {
      final database = FakeCloudflareD1Database();
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      return AuthWebAuthnStoreConformanceFixture(
        capabilities: store,
        dispose: database.close,
      );
    });
    for (final testCase in suite.cases) {
      test('conformance: ${testCase.id}', testCase.run);
    }

    test(
      'migration v10 is append-only and dropAll removes its tables',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        const schema = CloudflareD1AuthSchema(tablePrefix: 'passkey_history');

        await schema.migrate(database);

        expect(
          database
              .select(
                'SELECT version FROM ${schema.table('migrations')} '
                'ORDER BY version',
              )
              .map((row) => row['version']),
          orderedEquals(
            List<int>.generate(
              CloudflareD1AuthSchema.currentVersion,
              (index) => index + 1,
            ),
          ),
        );
        expect(
          database.select("SELECT name FROM sqlite_master WHERE name = ?", [
            schema.table('webauthn_challenges'),
          ]),
          hasLength(1),
        );
        expect(
          database.select("SELECT name FROM sqlite_master WHERE name = ?", [
            schema.table('webauthn_authenticators'),
          ]),
          hasLength(1),
        );

        await schema.dropAll(database);

        expect(
          database.select("SELECT name FROM sqlite_master WHERE name LIKE ?", [
            '${schema.tablePrefix}_%',
          ]),
          isEmpty,
        );
      },
    );

    test(
      'persists only the challenge digest and bounded safe metadata',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        const schema = CloudflareD1AuthSchema();
        final store = await CloudflareD1AuthStore.open(
          database,
          schema: schema,
          clock: () => _now,
        );
        const rawChallenge = 'one-time-browser-challenge';
        final challenge = _challenge(
          'secret-safe',
          challengeHash: hashOpaqueToken(rawChallenge),
        );

        await store.webAuthnChallenges.save(challenge);
        await store.webAuthnAuthenticators.create(_credential('secret-safe'));

        final challengeValues = database
            .select('SELECT * FROM ${schema.table('webauthn_challenges')}')
            .single
            .values
            .whereType<String>()
            .join('\n');
        final authenticator = database
            .select('SELECT * FROM ${schema.table('webauthn_authenticators')}')
            .single;
        expect(challengeValues, isNot(contains(rawChallenge)));
        expect(challengeValues, contains(hashOpaqueToken(rawChallenge)));
        expect(authenticator.keys, isNot(contains('attestation')));
        expect(authenticator['public_key'], 'cose-public-key-secret-safe');
        expect(authenticator['transports'], '["internal"]');
      },
    );

    test('challenge and authenticator capacities never overflow', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        webAuthnChallengeMaxRecords: 1,
        webAuthnAuthenticatorMaxRecords: 1,
        clock: () => _now,
      );

      await store.webAuthnChallenges.save(_challenge('first'));
      await expectLater(
        store.webAuthnChallenges.save(_challenge('second')),
        throwsStateError,
      );
      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('webauthn_challenges')}',
        ),
        hasLength(1),
      );

      await store.webAuthnAuthenticators.create(_credential('first'));
      await expectLater(
        store.webAuthnAuthenticators.create(_credential('second')),
        throwsStateError,
      );
      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('webauthn_authenticators')}',
        ),
        hasLength(1),
      );
    });

    test('challenge save rolls back when its D1 batch faults', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      database.failNextBatchAfterStatements(1);

      await expectLater(
        store.webAuthnChallenges.save(_challenge('faulted')),
        throwsStateError,
      );

      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('webauthn_challenges')}',
        ),
        isEmpty,
      );
      await store.webAuthnChallenges.save(_challenge('retry'));
      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('webauthn_challenges')}',
        ),
        hasLength(1),
      );
    });

    test(
      'hard deletion removes both stores in the coordinator batch',
      () async {
        final database = FakeCloudflareD1Database();
        addTearDown(database.close);
        final store = await CloudflareD1AuthStore.open(
          database,
          clock: () => _now,
        );
        final plugin = _plugin();
        _compose(store, plugin);
        store.bindUserDeletionPlanContributors([plugin]);
        await store.users.create(AuthUser(id: 'user-1'));
        await store.webAuthnChallenges.save(_challenge('delete'));
        await store.webAuthnAuthenticators.create(_credential('delete'));

        expect(
          await store.userDeletionCoordinator.deleteUser('user-1'),
          isTrue,
        );

        expect(await store.users.findById('user-1'), isNull);
        expect(
          await store.webAuthnAuthenticators.listForUser('user-1'),
          isEmpty,
        );
        expect(
          database.select(
            'SELECT * FROM ${store.schema.table('webauthn_challenges')}',
          ),
          isEmpty,
        );
      },
    );

    test('hard deletion rolls WebAuthn cleanup back with the user', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      final plugin = _plugin();
      _compose(store, plugin);
      store.bindUserDeletionPlanContributors([plugin]);
      await store.users.create(AuthUser(id: 'user-1'));
      await store.webAuthnChallenges.save(_challenge('rollback'));
      await store.webAuthnAuthenticators.create(_credential('rollback'));
      database.failNextBatchAfterStatements(1);

      await expectLater(
        store.userDeletionCoordinator.deleteUser('user-1'),
        throwsStateError,
      );

      expect(await store.users.findById('user-1'), isNotNull);
      expect(
        await store.webAuthnAuthenticators.listForUser('user-1'),
        hasLength(1),
      );
      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('webauthn_challenges')}',
        ),
        hasLength(1),
      );
      expect(await store.userDeletionCoordinator.deleteUser('user-1'), isTrue);
    });

    test('backend-owned cleanup survives WebAuthn plugin removal', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      store.bindUserDeletionPlanContributors(const []);
      await store.users.create(AuthUser(id: 'user-1'));
      await store.webAuthnChallenges.save(_challenge('removed-plugin'));
      await store.webAuthnAuthenticators.create(_credential('removed-plugin'));

      expect(await store.userDeletionCoordinator.deleteUser('user-1'), isTrue);

      expect(await store.webAuthnAuthenticators.listForUser('user-1'), isEmpty);
      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('webauthn_challenges')}',
        ),
        isEmpty,
      );
    });

    test('creation racing hard deletion cannot reactivate a user ID', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      store.bindUserDeletionPlanContributors(const []);
      await store.users.create(AuthUser(id: 'user-1'));

      final outcomes = await Future.wait<Object?>([
        store.userDeletionCoordinator.deleteUser('user-1'),
        store.webAuthnAuthenticators
            .create(_credential('racing-delete'))
            .then<Object?>((value) => value)
            .catchError((Object error) => error),
        store.webAuthnChallenges
            .save(_challenge('racing-delete'))
            .then<Object?>((_) => null)
            .catchError((Object error) => error),
      ]);

      expect(outcomes.first, isTrue);
      expect(await store.users.findById('user-1'), isNull);
      expect(await store.webAuthnAuthenticators.listForUser('user-1'), isEmpty);
      expect(
        database.select(
          'SELECT * FROM ${store.schema.table('webauthn_challenges')}',
        ),
        isEmpty,
      );
      await expectLater(
        store.webAuthnAuthenticators.create(_credential('after-delete')),
        throwsStateError,
      );
    });

    test('exact D1 topology preserves the last passkey', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      final plugin = _plugin();
      _compose(store, plugin);
      await store.webAuthnAuthenticators.create(_credential('first'));

      await expectLater(
        plugin.deleteCredential(
          userId: 'user-1',
          credentialId: 'credential-first',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'last_authentication_method',
          ),
        ),
      );
      await store.webAuthnAuthenticators.create(_credential('second'));

      await plugin.deleteCredential(
        userId: 'user-1',
        credentialId: 'credential-first',
      );

      expect(
        await store.webAuthnAuthenticators.findByCredentialId(
          'credential-first',
        ),
        isNull,
      );
      expect(
        await store.webAuthnAuthenticators.findByCredentialId(
          'credential-second',
        ),
        isNotNull,
      );
    });

    test('a same-domain API key is an exact passkey fallback', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      final passkeys = _plugin();
      final apiKeys = AuthApiKeyPlugin<Object>(
        store: store.apiKeys,
        countsAsPrimaryAuthenticationMethod: true,
        clock: () => _now,
      );
      final methods = AuthAuthenticationMethodService(store: store);
      passkeys.configure(
        AuthServerPluginContext<Object>(
          store: store,
          authenticationMethods: methods,
        ),
      );
      apiKeys.configure(
        AuthServerPluginContext<Object>(
          store: store,
          authenticationMethods: methods,
        ),
      );
      methods.composeContributors([passkeys, apiKeys]);
      await store.webAuthnAuthenticators.create(_credential('primary'));
      await apiKeys.issue(userId: 'user-1', name: 'Fallback');

      await passkeys.deleteCredential(
        userId: 'user-1',
        credentialId: 'credential-primary',
      );

      expect(
        await store.webAuthnAuthenticators.findByCredentialId(
          'credential-primary',
        ),
        isNull,
      );
    });

    test('a same-domain passkey is an exact API-key fallback', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      final passkeys = _plugin();
      final apiKeys = AuthApiKeyPlugin<Object>(
        store: store.apiKeys,
        countsAsPrimaryAuthenticationMethod: true,
        clock: () => _now,
      );
      final methods = AuthAuthenticationMethodService(store: store);
      passkeys.configure(
        AuthServerPluginContext<Object>(
          store: store,
          authenticationMethods: methods,
        ),
      );
      apiKeys.configure(
        AuthServerPluginContext<Object>(
          store: store,
          authenticationMethods: methods,
        ),
      );
      methods.composeContributors([passkeys, apiKeys]);
      await store.webAuthnAuthenticators.create(_credential('fallback'));
      final issued = await apiKeys.issue(userId: 'user-1', name: 'Primary');

      final revoked = await apiKeys.revoke(
        'user-1',
        issued.apiKey.id,
        now: _now,
      );

      expect(revoked, isNotNull);
      expect(revoked!.revokedAt, _now);
    });

    test('mixed passkey storage fails closed without deleting', () async {
      final database = FakeCloudflareD1Database();
      addTearDown(database.close);
      final store = await CloudflareD1AuthStore.open(
        database,
        clock: () => _now,
      );
      final plugin = _plugin();
      final methods = AuthAuthenticationMethodService(store: store);
      plugin.configure(
        AuthServerPluginContext<Object>(
          store: store,
          authenticationMethods: methods,
        ),
      );
      methods.composeContributors([
        plugin,
        _ForeignPasskeyContributor(InMemoryAuthWebAuthnAuthenticatorStore()),
      ]);
      await store.webAuthnAuthenticators.create(_credential('mixed'));

      await expectLater(
        plugin.deleteCredential(
          userId: 'user-1',
          credentialId: 'credential-mixed',
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'authentication_method_mutation_unavailable',
          ),
        ),
      );
      expect(
        await store.webAuthnAuthenticators.findByCredentialId(
          'credential-mixed',
        ),
        isNotNull,
      );
    });

    test(
      'hostile credential components are rejected or remain bound',
      () async {
        final generator = Gen.frequency<String>([
          (8, Chaos.string(minLength: 0, maxLength: 4300)),
          (
            2,
            Gen.oneOf([
              '',
              ' ',
              'credential\u0000admin',
              'credential\nadmin',
              "' OR 1=1 --",
              '../../passkeys',
              '<script>alert(1)</script>',
              '正常な認証器',
              'x' * 4097,
            ]),
          ),
        ]);
        final runner = PropertyTestRunner<String>(generator, (candidate) async {
          final database = FakeCloudflareD1Database();
          try {
            final store = await CloudflareD1AuthStore.open(
              database,
              clock: () => _now,
            );
            try {
              await store.webAuthnAuthenticators.create(
                _credential('property', credentialId: candidate),
              );
              expect(candidate, isNotEmpty);
              expect(candidate, candidate.trim());
              expect(candidate.length, lessThanOrEqualTo(4096));
              expect(
                candidate.runes.any((rune) => rune < 0x20 || rune == 0x7f),
                isFalse,
              );
              expect(
                await store.webAuthnAuthenticators.findByCredentialId(
                  candidate,
                ),
                isNotNull,
              );
            } on ArgumentError {
              expect(
                candidate.isEmpty ||
                    candidate != candidate.trim() ||
                    candidate.length > 4096 ||
                    candidate.runes.any((rune) => rune < 0x20 || rune == 0x7f),
                isTrue,
              );
            }
          } finally {
            database.close();
          }
        }, PropertyConfig(numTests: 200, seed: 20260820));

        final result = await runner.run();
        expect(result.success, isTrue, reason: _propertyReport(result));
      },
    );
  });
}

final DateTime _now = DateTime.utc(2030, 1, 1);

WebAuthnPlugin<Object> _plugin() => WebAuthnPlugin<Object>(
  provider: WebAuthnProvider(
    getUserInfo: (_, _, _) => null,
    getRelyingParty: (_, _) => const WebAuthnRelyingParty(
      id: 'example.com',
      name: 'Example',
      origin: 'https://example.com',
    ),
  ),
);

void _compose(CloudflareD1AuthStore store, WebAuthnPlugin<Object> plugin) {
  final methods = AuthAuthenticationMethodService(store: store);
  plugin.configure(
    AuthServerPluginContext<Object>(
      store: store,
      authenticationMethods: methods,
    ),
  );
  methods.composeContributors([plugin]);
}

AuthWebAuthnChallenge _challenge(String suffix, {String? challengeHash}) =>
    AuthWebAuthnChallenge(
      id: 'challenge-$suffix',
      challengeHash: challengeHash ?? hashOpaqueToken('raw-challenge-$suffix'),
      ceremony: AuthWebAuthnCeremony.authentication,
      relyingPartyId: 'example.com',
      origin: 'https://example.com',
      userId: 'user-1',
      createdAt: _now,
      expiresAt: _now.add(const Duration(minutes: 5)),
    );

WebAuthnAuthenticator _credential(String suffix, {String? credentialId}) =>
    WebAuthnAuthenticator(
      credentialId: credentialId ?? 'credential-$suffix',
      publicKey: 'cose-public-key-$suffix',
      counter: 0,
      userId: 'user-1',
      transports: const ['internal'],
      createdAt: _now,
      name: 'Passkey $suffix',
    );

String _propertyReport(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: ${result.error}; '
    'input=${result.failingInput}; seed=${result.seed}';

final class _ForeignPasskeyContributor
    implements
        AuthAuthenticationMethodInventoryContributor,
        AuthAuthenticationMethodInventoryBinding {
  const _ForeignPasskeyContributor(this.store);

  final AuthWebAuthnAuthenticatorStore store;

  @override
  String get authenticationMethodNamespace => 'webauthn:foreign';

  @override
  Object get authenticationMethodStore => store;

  @override
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds => const {
    AuthAuthenticationMethodKind.passkey,
  };

  @override
  Future<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String userId,
  ) async => AuthAuthenticationMethodSnapshot.complete(
    (await store.listForUser(
      userId,
    )).map((record) => AuthAuthenticationMethod.passkey(record.credentialId)),
  );
}
