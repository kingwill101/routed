import 'dart:convert';

import 'package:property_testing/property_testing.dart';
import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

const _verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
const _challenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

void main() {
  group('InMemoryOAuthAuthorizationCodeExchangeStore', () {
    test('passes public adapter conformance', () async {
      await verifyOAuthAuthorizationCodeExchangeStoreConformance(
        () => InMemoryOAuthAuthorizationCodeExchangeStore(),
      );
    });

    test('commits code consumption and token persistence together', () async {
      final fixture = await _fixture();
      final prepared = await fixture.store.prepare(fixture.request);
      expect(prepared.status, OAuthAuthorizationCodePreparationStatus.ready);

      final result = await fixture.store.commit(
        request: fixture.request,
        expectedAuthorizationId: fixture.code.authorizationId,
        preparedToken: fixture.token,
      );

      expect(result.status, OAuthAuthorizationCodeExchangeStatus.committed);
      expect(
        await fixture.tokens.findByToken(fixture.rawAccessToken),
        same(fixture.token),
      );
      expect(
        await fixture.codes.consume(
          codeHash: fixture.code.codeHash,
          clientId: fixture.code.clientId,
          redirectUri: fixture.code.redirectUri,
          codeVerifier: _verifier,
        ),
        isNull,
      );
    });

    for (final point in InMemoryOAuthCodeExchangeFaultPoint.values) {
      test('rolls back all state at ${point.name}', () async {
        var injected = false;
        final fixture = await _fixture(
          faultInjector: (candidate) {
            if (candidate == point && !injected) {
              injected = true;
              throw StateError('injected exchange storage failure');
            }
          },
        );

        await expectLater(
          fixture.store.commit(
            request: fixture.request,
            expectedAuthorizationId: fixture.code.authorizationId,
            preparedToken: fixture.token,
          ),
          throwsStateError,
        );

        expect(
          (await fixture.store.prepare(fixture.request)).status,
          OAuthAuthorizationCodePreparationStatus.ready,
        );
        expect(
          await fixture.tokens.findByToken(fixture.rawAccessToken),
          isNull,
        );
      });
    }

    test('allows one winner under concurrent exchange', () async {
      final fixture = await _fixture();
      final results = await Future.wait(
        List<Future<OAuthAuthorizationCodeExchangeResult>>.generate(
          24,
          (_) => fixture.store.commit(
            request: fixture.request,
            expectedAuthorizationId: fixture.code.authorizationId,
            preparedToken: fixture.token,
          ),
        ),
      );

      expect(
        results
            .where(
              (result) =>
                  result.status ==
                  OAuthAuthorizationCodeExchangeStatus.committed,
            )
            .length,
        1,
      );
      expect(
        results
            .where(
              (result) =>
                  result.status ==
                  OAuthAuthorizationCodeExchangeStatus.alreadyCommitted,
            )
            .length,
        23,
      );
    });

    for (final binding in <String>['client', 'redirect', 'verifier']) {
      test('wrong $binding binding consumes the matching digest', () async {
        final fixture = await _fixture();
        final wrong = OAuthAuthorizationCodeExchangeRequest(
          codeHash: fixture.request.codeHash,
          clientId: binding == 'client' ? 'wrong-client' : 'client-1',
          redirectUri: binding == 'redirect'
              ? 'https://wrong.example.test/callback'
              : fixture.request.redirectUri,
          codeVerifier: binding == 'verifier' ? 'wrong-verifier' : _verifier,
          now: fixture.request.now,
        );

        expect(
          (await fixture.store.prepare(wrong)).status,
          OAuthAuthorizationCodePreparationStatus.invalidGrant,
        );
        expect(
          (await fixture.store.prepare(fixture.request)).status,
          OAuthAuthorizationCodePreparationStatus.invalidGrant,
        );
      });
    }

    test('expired code cannot create a token', () async {
      final now = DateTime.utc(2030, 1, 1);
      final fixture = await _fixture(
        now: now,
        expiresAt: now.add(const Duration(seconds: 1)),
      );
      final expiredRequest = OAuthAuthorizationCodeExchangeRequest(
        codeHash: fixture.request.codeHash,
        clientId: fixture.request.clientId,
        redirectUri: fixture.request.redirectUri,
        codeVerifier: fixture.request.codeVerifier,
        now: now.add(const Duration(seconds: 2)),
      );

      expect(
        (await fixture.store.prepare(expiredRequest)).status,
        OAuthAuthorizationCodePreparationStatus.invalidGrant,
      );
      expect(await fixture.tokens.findByToken(fixture.rawAccessToken), isNull);
    });

    test('rejects authorization ID and code digest collisions', () async {
      final fixture = await _fixture();
      await expectLater(
        fixture.codes.create(
          _code(
            authorizationId: fixture.code.authorizationId,
            codeHash: hashOpaqueToken('another-code'),
            now: fixture.request.now,
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        fixture.codes.create(
          _code(
            authorizationId: 'another-authorization',
            codeHash: fixture.code.codeHash,
            now: fixture.request.now,
          ),
        ),
        throwsStateError,
      );
    });

    test('rejects a prepared token for another authorization', () async {
      final fixture = await _fixture();
      final wrong = fixture.token.copyWith(
        authorizationId: 'another-authorization',
      );

      await expectLater(
        fixture.store.commit(
          request: fixture.request,
          expectedAuthorizationId: fixture.code.authorizationId,
          preparedToken: wrong,
        ),
        throwsArgumentError,
      );
      expect(
        (await fixture.store.prepare(fixture.request)).status,
        OAuthAuthorizationCodePreparationStatus.ready,
      );
    });

    test(
      'digest-only persistence and errors never reveal raw values',
      () async {
        final secrets = Chaos.string(minLength: 24, maxLength: 96);
        final runner = PropertyTestRunner<String>(secrets, (secret) async {
          final now = DateTime.utc(2030, 1, 1);
          final codes = InMemoryOAuthAuthorizationCodeStore();
          final tokens = InMemoryOAuthAccessTokenStore();
          final store = InMemoryOAuthAuthorizationCodeExchangeStore(
            authorizationCodeStore: codes,
            accessTokenStore: tokens,
            faultInjector: (_) => throw StateError('storage unavailable'),
          );
          final code = _code(
            authorizationId: 'authorization-safe',
            codeHash: hashOpaqueToken(secret),
            now: now,
          );
          final token = _token(
            authorizationId: code.authorizationId,
            rawAccessToken: '$secret-access',
            rawRefreshToken: '$secret-refresh',
            now: now,
          );
          await codes.create(code);
          final request = _request(code, now: now);
          Object? failure;
          try {
            await store.commit(
              request: request,
              expectedAuthorizationId: code.authorizationId,
              preparedToken: token,
            );
          } catch (error) {
            failure = error;
          }
          final persisted = jsonEncode(<Object?>[
            code.toStorageJson(),
            token.tokenHash,
            token.refreshTokenHash,
            failure?.toString(),
            request.toString(),
          ]);
          expect(persisted, isNot(contains(secret)));
        }, PropertyConfig(numTests: 300, seed: 20260820));

        final result = await runner.run();
        expect(result.success, isTrue, reason: _propertyReport(result));
      },
    );
  });
}

Future<
  ({
    InMemoryOAuthAuthorizationCodeExchangeStore store,
    InMemoryOAuthAuthorizationCodeStore codes,
    InMemoryOAuthAccessTokenStore tokens,
    OAuthAuthorizationCode code,
    OAuthAuthorizationCodeExchangeRequest request,
    OAuthAccessToken token,
    String rawAccessToken,
  })
>
_fixture({
  DateTime? now,
  DateTime? expiresAt,
  InMemoryOAuthCodeExchangeFaultInjector? faultInjector,
}) async {
  final current = now ?? DateTime.utc(2030, 1, 1);
  const rawAccessToken = 'delivery-only-access-token';
  final codes = InMemoryOAuthAuthorizationCodeStore();
  final tokens = InMemoryOAuthAccessTokenStore();
  final store = InMemoryOAuthAuthorizationCodeExchangeStore(
    authorizationCodeStore: codes,
    accessTokenStore: tokens,
    faultInjector: faultInjector,
  );
  final code = _code(
    authorizationId: 'authorization-1',
    codeHash: hashOpaqueToken('delivery-only-code'),
    now: current,
    expiresAt: expiresAt,
  );
  final token = _token(
    authorizationId: code.authorizationId,
    rawAccessToken: rawAccessToken,
    rawRefreshToken: 'delivery-only-refresh-token',
    now: current,
  );
  await codes.create(code);
  return (
    store: store,
    codes: codes,
    tokens: tokens,
    code: code,
    request: _request(code, now: current),
    token: token,
    rawAccessToken: rawAccessToken,
  );
}

OAuthAuthorizationCode _code({
  required String authorizationId,
  required String codeHash,
  required DateTime now,
  DateTime? expiresAt,
}) => OAuthAuthorizationCode(
  authorizationId: authorizationId,
  codeHash: codeHash,
  clientId: 'client-1',
  userId: 'user-1',
  redirectUri: 'https://client.example.test/callback',
  scope: 'openid profile',
  expiresAt: expiresAt ?? now.add(const Duration(minutes: 10)),
  codeChallenge: _challenge,
  codeChallengeMethod: 'S256',
  nonce: 'nonce-1',
  createdAt: now.subtract(const Duration(seconds: 1)),
);

OAuthAuthorizationCodeExchangeRequest _request(
  OAuthAuthorizationCode code, {
  required DateTime now,
}) => OAuthAuthorizationCodeExchangeRequest(
  codeHash: code.codeHash,
  clientId: code.clientId,
  redirectUri: code.redirectUri,
  codeVerifier: _verifier,
  now: now,
);

OAuthAccessToken _token({
  required String authorizationId,
  required String rawAccessToken,
  required String rawRefreshToken,
  required DateTime now,
}) => OAuthAccessToken(
  tokenHash: hashOpaqueToken(rawAccessToken),
  clientId: 'client-1',
  userId: 'user-1',
  scope: 'openid profile',
  expiresAt: now.add(const Duration(hours: 1)),
  refreshTokenHash: hashOpaqueToken(rawRefreshToken),
  refreshTokenExpiresAt: now.add(const Duration(days: 30)),
  issuedAt: now,
  authorizationId: authorizationId,
);

String _propertyReport(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: ${result.error}; '
    'input=${result.failingInput}; seed=${result.seed}';
