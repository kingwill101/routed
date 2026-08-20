import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  group('managed SCIM store conformance', () {
    final suite = AuthScimConnectionStoreConformanceSuite(
      () => AuthScimConnectionStoreConformanceFixture(
        store: InMemoryAuthScimConnectionStore(),
      ),
    );
    for (final testCase in suite.cases) {
      test(testCase.id, testCase.run);
    }
  });

  group('managed SCIM issuance', () {
    test(
      'raw credential is returned once and only a digest is stored',
      () async {
        final clock = _Clock();
        final store = InMemoryAuthScimConnectionStore();
        final plugin = _plugin(store, clock);
        final first = await plugin.create(
          principal: _principal,
          name: 'Acme Directory',
          provisioningDomainId: 'employees',
          scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
          credentialName: 'Primary',
          idempotencyKey: 'create-acme',
        );
        final replay = await plugin.create(
          principal: _principal,
          name: 'Acme Directory',
          provisioningDomainId: 'employees',
          scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
          credentialName: 'Primary',
          idempotencyKey: 'create-acme',
        );

        expect(first.issuance.secret, startsWith('rscim.'));
        expect(first.issuance.replayed, isFalse);
        expect(replay.connection.id, first.connection.id);
        expect(replay.issuance.credential.id, first.issuance.credential.id);
        expect(replay.issuance.secret, isNull);
        expect(replay.issuance.replayed, isTrue);

        final resolver = AuthScimManagedBearerTokenResolver<Object>(
          store: store,
          clock: clock.call,
        );
        final identity = await resolver.resolve(
          AuthScimBearerTokenRequest<Object>(
            context: Object(),
            token: first.issuance.secret!,
          ),
        );
        expect(identity?.connectionId, first.connection.id);
        expect(identity?.credentialId, first.issuance.credential.id);
        expect(identity?.tenantId, _principal.tenantId);
        expect(identity?.scopes, {AuthScimScope.usersWrite});

        final storage = await store.listCredentials(
          AuthScimCredentialCatalogQuery(
            binding: _principal.binding,
            connectionId: first.connection.id,
          ),
          now: clock.call(),
        );
        expect(
          storage.items.single.toJson().toString(),
          isNot(contains('secret')),
        );
        expect(
          storage.items.single.toJson().toString(),
          isNot(contains('digest')),
        );
      },
    );

    test('idempotency key cannot be rebound to another request', () async {
      final store = InMemoryAuthScimConnectionStore();
      final plugin = _plugin(store, _Clock());
      await plugin.create(
        principal: _principal,
        name: 'Directory A',
        provisioningDomainId: 'employees',
        scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
        credentialName: 'Primary',
        idempotencyKey: 'same-key',
      );
      await expectLater(
        () => plugin.create(
          principal: _principal,
          name: 'Directory B',
          provisioningDomainId: 'employees',
          scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
          credentialName: 'Primary',
          idempotencyKey: 'same-key',
        ),
        throwsA(
          isA<AuthScimConnectionStoreException>().having(
            (error) => error.failure,
            'failure',
            AuthScimConnectionStoreFailure.replayMismatch,
          ),
        ),
      );
    });

    test('rotation is one-time and old bearer immediately fails', () async {
      final clock = _Clock();
      final store = InMemoryAuthScimConnectionStore(
        maxCredentialsPerConnection: 1,
      );
      final plugin = _plugin(store, clock);
      final created = await plugin.create(
        principal: _principal,
        name: 'Directory',
        provisioningDomainId: 'employees',
        scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
        credentialName: 'Primary',
        idempotencyKey: 'create',
      );
      clock.advance(const Duration(minutes: 1));
      final rotated = await plugin.rotateCredential(
        principal: _principal,
        connectionId: created.connection.id,
        credentialId: created.issuance.credential.id,
        name: 'Replacement',
        scopes: const <AuthScimScope>{AuthScimScope.usersRead},
        idempotencyKey: 'rotate',
      );
      expect(rotated?.secret, isNotNull);
      final resolver = AuthScimManagedBearerTokenResolver<Object>(
        store: store,
        clock: clock.call,
      );
      expect(
        await resolver.resolve(
          AuthScimBearerTokenRequest<Object>(
            context: Object(),
            token: created.issuance.secret!,
          ),
        ),
        isNull,
      );
      expect(
        (await resolver.resolve(
          AuthScimBearerTokenRequest<Object>(
            context: Object(),
            token: rotated!.secret!,
          ),
        ))?.scopes,
        {AuthScimScope.usersRead},
      );
      final replay = await plugin.rotateCredential(
        principal: _principal,
        connectionId: created.connection.id,
        credentialId: created.issuance.credential.id,
        name: 'Replacement',
        scopes: const <AuthScimScope>{AuthScimScope.usersRead},
        idempotencyKey: 'rotate',
      );
      expect(replay?.secret, isNull);
      expect(replay?.credential.id, rotated.credential.id);
      final createReplay = await plugin.create(
        principal: _principal,
        name: 'Directory',
        provisioningDomainId: 'employees',
        scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
        credentialName: 'Primary',
        idempotencyKey: 'create',
      );
      expect(createReplay.issuance.secret, isNull);
      expect(createReplay.issuance.credential.active, isFalse);
    });
  });

  group('managed SCIM atomicity', () {
    test(
      'faulted create rolls back connection, credential, and replay',
      () async {
        var fail = true;
        final store = InMemoryAuthScimConnectionStore(
          injectFault: (operation) {
            if (fail && operation == 'createConnection') {
              fail = false;
              throw StateError('injected commit failure');
            }
          },
        );
        final plugin = _plugin(store, _Clock());
        await expectLater(
          () => plugin.create(
            principal: _principal,
            name: 'Directory',
            provisioningDomainId: 'employees',
            scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
            credentialName: 'Primary',
            idempotencyKey: 'create',
          ),
          throwsStateError,
        );
        expect((await plugin.list(principal: _principal)).total, 0);
        final retry = await plugin.create(
          principal: _principal,
          name: 'Directory',
          provisioningDomainId: 'employees',
          scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
          credentialName: 'Primary',
          idempotencyKey: 'create',
        );
        expect(retry.issuance.secret, isNotNull);
        expect(retry.issuance.replayed, isFalse);
      },
    );

    test('faulted disable restores connection and every credential', () async {
      var failDisable = false;
      final clock = _Clock();
      final store = InMemoryAuthScimConnectionStore(
        injectFault: (operation) {
          if (failDisable && operation == 'disableConnection') {
            throw StateError('injected disable failure');
          }
        },
      );
      final plugin = _plugin(store, clock);
      final created = await plugin.create(
        principal: _principal,
        name: 'Directory',
        provisioningDomainId: 'employees',
        scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
        credentialName: 'Primary',
        idempotencyKey: 'create',
      );
      failDisable = true;
      await expectLater(
        () => plugin.disable(
          principal: _principal,
          connectionId: created.connection.id,
        ),
        throwsStateError,
      );
      failDisable = false;
      expect(
        (await store.findConnection(
          _principal.binding,
          created.connection.id,
        ))?.isActive,
        isTrue,
      );
      expect(
        await AuthScimManagedBearerTokenResolver<Object>(
          store: store,
          clock: clock.call,
        ).resolve(
          AuthScimBearerTokenRequest<Object>(
            context: Object(),
            token: created.issuance.secret!,
          ),
        ),
        isNotNull,
      );
    });

    test('scope narrowing revokes credentials outside the new grant', () async {
      final clock = _Clock();
      final store = InMemoryAuthScimConnectionStore();
      final plugin = _plugin(store, clock);
      final created = await plugin.create(
        principal: _principal,
        name: 'Directory',
        provisioningDomainId: 'employees',
        scopes: const <AuthScimScope>{
          AuthScimScope.usersWrite,
          AuthScimScope.groupsWrite,
        },
        credentialName: 'Primary',
        idempotencyKey: 'create',
      );
      clock.advance(const Duration(minutes: 1));
      final updated = await plugin.update(
        principal: _principal,
        connectionId: created.connection.id,
        expectedUpdatedAt: created.connection.updatedAt,
        name: created.connection.name,
        provisioningDomainId: created.connection.provisioningDomainId,
        scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
      );
      expect(updated?.scopes, {AuthScimScope.usersWrite});
      expect(
        await AuthScimManagedBearerTokenResolver<Object>(
          store: store,
          clock: clock.call,
        ).resolve(
          AuthScimBearerTokenRequest<Object>(
            context: Object(),
            token: created.issuance.secret!,
          ),
        ),
        isNull,
      );
    });

    test('subject and tenant deletion leave no live bearer', () async {
      final clock = _Clock();
      final store = InMemoryAuthScimConnectionStore();
      final plugin = _plugin(store, clock);
      final subjectOwned = await plugin.create(
        principal: _principal,
        name: 'Subject directory',
        provisioningDomainId: 'employees',
        scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
        credentialName: 'Primary',
        idempotencyKey: 'subject',
      );
      await store.deleteForSubject(_principal.subjectId);
      expect(
        await _resolve(store, clock, subjectOwned.issuance.secret!),
        isNull,
      );

      final tenantOwned = await plugin.create(
        principal: _principal,
        name: 'Tenant directory',
        provisioningDomainId: 'employees',
        scopes: const <AuthScimScope>{AuthScimScope.usersWrite},
        credentialName: 'Primary',
        idempotencyKey: 'tenant',
      );
      await plugin.deleteTenant(_principal.tenantId);
      expect(
        await _resolve(store, clock, tenantOwned.issuance.secret!),
        isNull,
      );
    });
  });
}

final AuthScimConnectionManagementPrincipal _principal =
    AuthScimConnectionManagementPrincipal(
      tenantId: 'tenant-a',
      organizationId: 'organization-a',
      subjectId: 'user-a',
    );

AuthScimConnectionPlugin<Object> _plugin(
  AuthScimConnectionStore store,
  _Clock clock,
) {
  var connectionSequence = 0;
  var credentialSequence = 0;
  var secretSequence = 0;
  return AuthScimConnectionPlugin<Object>(
    store: store,
    authorize: (_) => _principal,
    clock: clock.call,
    connectionIdGenerator: ({length = 0}) =>
        'connection-${++connectionSequence}-abcdefgh',
    credentialIdGenerator: ({length = 0}) =>
        'credential-${++credentialSequence}-abcdefgh',
    secretGenerator: ({length = 0}) =>
        'secret-${++secretSequence}-abcdefghijklmnopqrstuvwxyz',
  );
}

Future<AuthScimConnectionIdentity?> _resolve(
  AuthScimConnectionStore store,
  _Clock clock,
  String secret,
) => AuthScimManagedBearerTokenResolver<Object>(
  store: store,
  clock: clock.call,
).resolve(AuthScimBearerTokenRequest<Object>(context: Object(), token: secret));

final class _Clock {
  DateTime _now = DateTime.utc(2030, 1, 1, 12);

  DateTime call() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}
