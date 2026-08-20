import 'dart:async';

import '../core/oauth_client_store.dart';
import '../core/oauth_provider_models.dart';
import '../core/tokens.dart' show hashOpaqueToken;

/// Creates a fresh, isolated exchange store for each conformance case.
typedef OAuthAuthorizationCodeExchangeStoreFactory =
    FutureOr<OAuthAuthorizationCodeExchangeStore> Function();

/// Failure reported by authorization-code exchange adapter conformance.
final class OAuthAuthorizationCodeExchangeConformanceFailure
    implements Exception {
  const OAuthAuthorizationCodeExchangeConformanceFailure(
    this.caseId,
    this.cause,
  );

  final String caseId;
  final Object cause;

  @override
  String toString() =>
      'OAuthAuthorizationCodeExchangeConformanceFailure($caseId): $cause';
}

/// Verifies the portable atomic exchange contract for a persistence adapter.
///
/// Durable adapters should run this function in their own test suite against
/// an isolated database namespace. Passing these cases does not certify a
/// backend transaction implementation; adapter authors must additionally
/// fault the database commit itself and prove rollback.
Future<void> verifyOAuthAuthorizationCodeExchangeStoreConformance(
  OAuthAuthorizationCodeExchangeStoreFactory createStore,
) async {
  await _case('exchange.commit', () async {
    final fixture = await _fixture(await createStore(), 'commit');
    final result = await fixture.store.commit(
      request: fixture.request,
      expectedAuthorizationId: fixture.code.authorizationId,
      preparedToken: fixture.token,
    );
    _check(
      result.status == OAuthAuthorizationCodeExchangeStatus.committed,
      'exchange did not commit',
    );
    _check(
      await fixture.store.accessTokenStore.findByToken(fixture.rawToken) !=
          null,
      'prepared token was not persisted',
    );
  });

  await _case('exchange.concurrent-one-winner', () async {
    final fixture = await _fixture(await createStore(), 'concurrent');
    final results = await Future.wait(
      List<Future<OAuthAuthorizationCodeExchangeResult>>.generate(
        16,
        (_) async => fixture.store.commit(
          request: fixture.request,
          expectedAuthorizationId: fixture.code.authorizationId,
          preparedToken: fixture.token,
        ),
      ),
    );
    _check(
      results
              .where(
                (result) =>
                    result.status ==
                    OAuthAuthorizationCodeExchangeStatus.committed,
              )
              .length ==
          1,
      'exchange had more than one winner',
    );
    _check(
      results.every(
        (result) =>
            result.status == OAuthAuthorizationCodeExchangeStatus.committed ||
            result.status ==
                OAuthAuthorizationCodeExchangeStatus.alreadyCommitted,
      ),
      'contending retry returned an unexpected result',
    );
  });

  await _case('exchange.wrong-binding-consumes', () async {
    final fixture = await _fixture(await createStore(), 'wrong-binding');
    final wrong = OAuthAuthorizationCodeExchangeRequest(
      codeHash: fixture.request.codeHash,
      clientId: fixture.request.clientId,
      redirectUri: fixture.request.redirectUri,
      codeVerifier: 'wrong-verifier',
      now: fixture.request.now,
    );
    _check(
      (await fixture.store.prepare(wrong)).status ==
          OAuthAuthorizationCodePreparationStatus.invalidGrant,
      'wrong binding was accepted',
    );
    _check(
      (await fixture.store.prepare(fixture.request)).status ==
          OAuthAuthorizationCodePreparationStatus.invalidGrant,
      'wrong binding did not consume the matching digest',
    );
  });

  await _case('exchange.authorization-id-collision', () async {
    final fixture = await _fixture(await createStore(), 'collision');
    var rejected = false;
    try {
      await fixture.store.authorizationCodeStore.create(
        _code(
          namespace: 'collision-other',
          authorizationId: fixture.code.authorizationId,
          codeHash: hashOpaqueToken('collision-other-code'),
        ),
      );
    } on StateError {
      rejected = true;
    }
    _check(rejected, 'duplicate authorization ID was accepted');
  });
}

Future<
  ({
    OAuthAuthorizationCodeExchangeStore store,
    OAuthAuthorizationCode code,
    OAuthAuthorizationCodeExchangeRequest request,
    OAuthAccessToken token,
    String rawToken,
  })
>
_fixture(OAuthAuthorizationCodeExchangeStore store, String namespace) async {
  final code = _code(
    namespace: namespace,
    authorizationId: '$namespace-authorization',
    codeHash: hashOpaqueToken('$namespace-code'),
  );
  const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
  final request = OAuthAuthorizationCodeExchangeRequest(
    codeHash: code.codeHash,
    clientId: code.clientId,
    redirectUri: code.redirectUri,
    codeVerifier: verifier,
    now: DateTime.utc(2030, 1, 1),
  );
  final rawToken = '$namespace-access-token';
  final token = OAuthAccessToken(
    tokenHash: hashOpaqueToken(rawToken),
    clientId: code.clientId,
    userId: code.userId,
    scope: code.scope,
    expiresAt: DateTime.utc(2030, 1, 1, 1),
    issuedAt: DateTime.utc(2030, 1, 1),
    authorizationId: code.authorizationId,
  );
  await store.authorizationCodeStore.create(code);
  return (
    store: store,
    code: code,
    request: request,
    token: token,
    rawToken: rawToken,
  );
}

OAuthAuthorizationCode _code({
  required String namespace,
  required String authorizationId,
  required String codeHash,
}) => OAuthAuthorizationCode(
  authorizationId: authorizationId,
  codeHash: codeHash,
  clientId: '$namespace-client',
  userId: '$namespace-user',
  redirectUri: 'https://$namespace.example.test/callback',
  scope: 'profile',
  expiresAt: DateTime.utc(2030, 1, 1, 0, 10),
  codeChallenge: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
  codeChallengeMethod: 'S256',
  createdAt: DateTime.utc(2030, 1, 1),
);

Future<void> _case(String id, Future<void> Function() body) async {
  try {
    await body();
  } on OAuthAuthorizationCodeExchangeConformanceFailure {
    rethrow;
  } catch (error) {
    throw OAuthAuthorizationCodeExchangeConformanceFailure(id, error);
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
