import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('AuthApiKeyFeature', () {
    test('stores only a digest and authenticates the raw key', () async {
      final store = InMemoryAuthApiKeyStore();
      final feature = AuthApiKeyFeature<Never>(
        store: store,
        keyIdGenerator: _queuedGenerator(['key-id']),
        secretGenerator: _queuedGenerator(['secret-value']),
      );

      final issued = await feature.issue(
        userId: 'user-1',
        name: 'deploy',
        scopes: const ['Deploy:Write', 'deploy:write', 'read'],
      );
      final persisted = await store.findById(issued.apiKey.id);

      expect(issued.key, isNot(contains('secret_hash')));
      expect(persisted, isNotNull);
      expect(persisted!.secretHash, isNot(issued.key));
      expect(persisted.toStorageJson()['secret_hash'], isNot(issued.key));
      expect(persisted.scopes, equals(['deploy:write', 'read']));

      final authentication = await feature.authenticate(issued.key);
      expect(authentication?.record.id, issued.apiKey.id);
      expect(authentication?.record.lastUsedAt, isNotNull);
      expect(await feature.authenticate('rka.invalid.secret'), isNull);
    });

    test('rejects expired and revoked keys', () async {
      final store = InMemoryAuthApiKeyStore();
      final feature = AuthApiKeyFeature<Never>(
        store: store,
        keyIdGenerator: _queuedGenerator(['expired', 'active']),
        secretGenerator: _queuedGenerator(['expired-secret', 'active-secret']),
      );
      final issuedAt = DateTime.utc(2026, 1, 1);
      final expired = await feature.issue(
        userId: 'user-1',
        name: 'expired',
        expiresAt: issuedAt.add(const Duration(minutes: 1)),
        now: issuedAt,
      );
      final active = await feature.issue(
        userId: 'user-1',
        name: 'active',
        now: issuedAt,
      );

      expect(
        await feature.authenticate(
          expired.key,
          now: issuedAt.add(const Duration(minutes: 2)),
        ),
        isNull,
      );
      expect(await feature.revoke('user-1', active.apiKey.id), isNotNull);
      expect(await feature.authenticate(active.key), isNull);
      expect(await feature.revoke('other-user', active.apiKey.id), isNull);
    });

    test('rotates keys atomically and invalidates the old secret', () async {
      final store = InMemoryAuthApiKeyStore();
      final feature = AuthApiKeyFeature<Never>(
        store: store,
        keyIdGenerator: _queuedGenerator(['old-id', 'new-id']),
        secretGenerator: _queuedGenerator(['old-secret', 'new-secret']),
      );
      final issued = await feature.issue(userId: 'user-1', name: 'worker');
      final rotated = await feature.rotate(
        'user-1',
        issued.apiKey.id,
        scopes: const ['jobs:read'],
      );

      expect(rotated, isNotNull);
      expect(rotated!.apiKey.id, isNot(issued.apiKey.id));
      expect(await feature.authenticate(issued.key), isNull);
      expect(
        (await feature.authenticate(rotated.key))?.record.userId,
        'user-1',
      );
      expect((await feature.list('user-1')), hasLength(2));
    });

    test('rejects unsafe scopes and excessive expiry', () async {
      final feature = AuthApiKeyFeature<Never>(
        store: InMemoryAuthApiKeyStore(),
        keyIdGenerator: _queuedGenerator(['key-id']),
        secretGenerator: _queuedGenerator(['secret']),
      );

      expect(
        () => feature.issue(
          userId: 'user-1',
          name: 'key',
          scopes: const ['not safe'],
        ),
        throwsArgumentError,
      );
      expect(
        () => feature.issue(
          userId: 'user-1',
          name: 'key',
          expiresAt: DateTime.utc(2030),
          now: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });

    test('uses the feature clock for public active metadata', () async {
      final clockTime = DateTime.utc(2026, 1, 1);
      var current = clockTime;
      final feature = AuthApiKeyFeature<Never>(
        store: InMemoryAuthApiKeyStore(),
        clock: () => current,
        keyIdGenerator: _queuedGenerator(['key-id']),
        secretGenerator: _queuedGenerator(['secret']),
      );

      final issued = await feature.issue(userId: 'user-1', name: 'worker');
      expect(issued.apiKey.active, isTrue);
      expect((await feature.list('user-1')).single.active, isTrue);
      expect(await feature.authenticate(issued.key), isNotNull);

      current = clockTime.add(const Duration(days: 91));
      expect((await feature.list('user-1')).single.active, isFalse);
      expect(await feature.authenticate(issued.key), isNull);
    });

    test('advertises atomic API-key lifecycle operations', () {
      final feature = AuthApiKeyFeature<Never>(
        store: InMemoryAuthApiKeyStore(),
      );
      final operations = feature.persistenceSchemas.single.atomicOperations
          .map((operation) => operation.id)
          .toSet();

      expect(
        operations,
        containsAll(<String>[
          'api_key.touch_if_active',
          'api_key.revoke_for_user',
          'api_key.rotate_for_user',
        ]),
      );
    });
  });
}

AuthApiKeyTokenGenerator _queuedGenerator(List<String> values) {
  var index = 0;
  return ({int length = 32}) {
    if (index >= values.length) throw StateError('token queue exhausted');
    return values[index++];
  };
}
