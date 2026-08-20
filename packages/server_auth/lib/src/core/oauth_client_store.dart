import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'deletion_transaction.dart';
import 'oauth_provider_models.dart';
import 'tokens.dart' show constantTimeStringEquals, hashOpaqueToken;

/// Persistence contract for OAuth clients.
abstract interface class OAuthClientStore {
  /// Finds a client by its ID.
  FutureOr<OAuthClient?> findById(String clientId);

  /// Lists all clients.
  FutureOr<List<OAuthClient>> listAll();

  /// Creates a new client.
  FutureOr<OAuthClient> create(OAuthClient client);

  /// Updates an existing client.
  FutureOr<OAuthClient> update(OAuthClient client);

  /// Deletes a client.
  FutureOr<void> delete(String clientId);

  /// Validates a client secret.
  FutureOr<bool> validateSecret(String clientId, String secret);
}

/// Persistence contract for authorization codes.
abstract interface class OAuthAuthorizationCodeStore {
  /// Creates an authorization code and rejects duplicate code hashes.
  FutureOr<OAuthAuthorizationCode> create(OAuthAuthorizationCode code);

  /// Atomically consumes a code after validating all protocol bindings.
  ///
  /// A matching code is invalidated even when a binding is wrong, preventing
  /// retries with a captured authorization code.
  FutureOr<OAuthAuthorizationCode?> consume({
    required String codeHash,
    required String clientId,
    required String redirectUri,
    required String? codeVerifier,
    DateTime? now,
  });

  /// Deletes expired codes.
  FutureOr<int> deleteExpired({DateTime? now});

  /// Deletes unconsumed codes owned by a user.
  FutureOr<void> deleteForUser(String userId);
}

/// Persistence contract for access tokens.
abstract interface class OAuthAccessTokenStore {
  /// Saves an access token.
  FutureOr<void> save(OAuthAccessToken token);

  /// Finds a token by its value.
  FutureOr<OAuthAccessToken?> findByToken(String token);

  /// Finds a token by its refresh token value.
  FutureOr<OAuthAccessToken?> findByRefreshToken(String refreshToken);

  /// Atomically validates and consumes [refreshToken], replacing its token
  /// record with [replacement]. The compare against [expectedTokenHash] prevents
  /// two concurrent refreshes from succeeding from the same snapshot.
  FutureOr<OAuthAccessToken?> rotateRefreshToken({
    required String refreshToken,
    required String expectedTokenHash,
    required OAuthAccessToken replacement,
    int? maxUses,
  });

  /// Revokes a token.
  FutureOr<void> revoke(String token);

  /// Revokes all tokens for a user.
  FutureOr<int> revokeAllForUser(String userId);

  /// Revokes all tokens for a client.
  FutureOr<int> revokeAllForClient(String clientId);

  /// Deletes expired tokens.
  FutureOr<int> deleteExpired({DateTime? now});
}

/// Identifies OAuth provider persistence that is authoritative when durable.
///
/// The client store and authorization-code exchange store must expose the
/// identical domain object. This prevents a durable runtime from booting with
/// split databases or with only part of provider-mode state made durable.
abstract interface class OAuthProviderPersistenceTopology {
  /// Backend-owned domain shared by the client registry and exchange store.
  AuthUserDeletionDomain get oauthProviderPersistenceDomain;
}

/// Digest-only bindings presented during an authorization-code exchange.
final class OAuthAuthorizationCodeExchangeRequest {
  const OAuthAuthorizationCodeExchangeRequest({
    required this.codeHash,
    required this.clientId,
    required this.redirectUri,
    required this.codeVerifier,
    required this.now,
  });

  /// Digest of the one-time authorization code.
  final String codeHash;
  final String clientId;
  final String redirectUri;
  final String? codeVerifier;
  final DateTime now;
}

/// Result of checking exchange bindings without consuming a valid code.
///
/// A store must consume a matching code digest when any supplied binding is
/// wrong. A ready result remains subject to the atomic [commit] comparison.
enum OAuthAuthorizationCodePreparationStatus { ready, invalidGrant }

final class OAuthAuthorizationCodePreparation {
  const OAuthAuthorizationCodePreparation._(this.status, this.authorization);

  const OAuthAuthorizationCodePreparation.ready(
    OAuthAuthorizationCode authorization,
  ) : this._(OAuthAuthorizationCodePreparationStatus.ready, authorization);

  const OAuthAuthorizationCodePreparation.invalidGrant()
    : this._(OAuthAuthorizationCodePreparationStatus.invalidGrant, null);

  final OAuthAuthorizationCodePreparationStatus status;
  final OAuthAuthorizationCode? authorization;
}

/// Result of the backend-owned code-consumption and token-persistence commit.
enum OAuthAuthorizationCodeExchangeStatus {
  committed,
  invalidGrant,
  alreadyCommitted,
}

/// Atomic authorization-code exchange result.
///
/// No result contains raw code or token material. [alreadyCommitted] tells the
/// caller that a previous request won, but does not promise response replay.
final class OAuthAuthorizationCodeExchangeResult {
  const OAuthAuthorizationCodeExchangeResult(this.status);

  final OAuthAuthorizationCodeExchangeStatus status;
}

/// Authoritative persistence capability for authorization-code grants.
///
/// Implementations own the authorization-code and access-token stores used by
/// provider mode. [commit] must atomically:
///
/// 1. revalidate the code digest, authorization ID, client, redirect URI,
///    S256 verifier, and expiry;
/// 2. consume the code; and
/// 3. persist [preparedToken], which contains digests only.
///
/// Durable implementations must use a backend transaction implemented by the
/// adapter. Callback-style transactions are intentionally not part of this
/// API. Raw authorization codes and raw access or refresh tokens must never be
/// persisted, logged, serialized, or included in errors.
abstract interface class OAuthAuthorizationCodeExchangeStore {
  OAuthAuthorizationCodeStore get authorizationCodeStore;
  OAuthAccessTokenStore get accessTokenStore;

  /// Checks bindings and returns the persisted authorization needed to prepare
  /// token digests and an OIDC ID token before commit.
  ///
  /// A code with a matching digest but wrong binding is consumed. A correctly
  /// bound code is not consumed until [commit], allowing account and client
  /// eligibility checks to fail without burning it.
  FutureOr<OAuthAuthorizationCodePreparation> prepare(
    OAuthAuthorizationCodeExchangeRequest request,
  );

  /// Atomically consumes [expectedAuthorizationId] and saves [preparedToken].
  FutureOr<OAuthAuthorizationCodeExchangeResult> commit({
    required OAuthAuthorizationCodeExchangeRequest request,
    required String expectedAuthorizationId,
    required OAuthAccessToken preparedToken,
  });
}

/// Fault points exposed by the in-memory adapter for rollback tests.
enum InMemoryOAuthCodeExchangeFaultPoint {
  afterCodeConsumption,
  afterTokenSave,
}

typedef InMemoryOAuthCodeExchangeFaultInjector =
    FutureOr<void> Function(InMemoryOAuthCodeExchangeFaultPoint point);

/// In-memory OAuth client store for tests and development.
class InMemoryOAuthClientStore implements OAuthClientStore {
  final Map<String, OAuthClient> _clients = {};

  @override
  Future<OAuthClient?> findById(String clientId) async {
    return _clients[clientId.trim()];
  }

  @override
  Future<List<OAuthClient>> listAll() async {
    return List.unmodifiable(_clients.values);
  }

  @override
  Future<OAuthClient> create(OAuthClient client) async {
    if (_clients.containsKey(client.clientId)) {
      throw StateError('Client already exists');
    }
    _clients[client.clientId] = client;
    return client;
  }

  @override
  Future<OAuthClient> update(OAuthClient client) async {
    if (!_clients.containsKey(client.clientId)) {
      throw StateError('Client not found');
    }
    _clients[client.clientId] = client;
    return client;
  }

  @override
  Future<void> delete(String clientId) async {
    _clients.remove(clientId.trim());
  }

  @override
  Future<bool> validateSecret(String clientId, String secret) async {
    final client = _clients[clientId.trim()];
    if (client == null || secret.isEmpty) return false;
    final digest = sha256.convert(utf8.encode(secret)).toString();
    return constantTimeStringEquals(digest, client.clientSecretHash);
  }
}

/// In-memory authorization code store for tests and development.
class InMemoryOAuthAuthorizationCodeStore
    implements OAuthAuthorizationCodeStore, AuthInMemoryUserDeletionStore {
  InMemoryOAuthAuthorizationCodeStore({this.maxEntries = 1024})
    : assert(maxEntries > 0);

  final int maxEntries;
  final Map<String, OAuthAuthorizationCode> _codes = {};

  @override
  Object captureDeletionState() =>
      Map<String, OAuthAuthorizationCode>.of(_codes);

  @override
  void restoreDeletionState(Object checkpoint) {
    final codes = checkpoint as Map<String, OAuthAuthorizationCode>;
    _codes
      ..clear()
      ..addAll(codes);
  }

  @override
  Future<OAuthAuthorizationCode> create(OAuthAuthorizationCode code) async {
    _validateAuthorizationCode(code);
    final now = DateTime.now().toUtc();
    _codes.removeWhere((_, value) => !value.isValid(now: now));
    if (_codes.containsKey(code.codeHash) ||
        _codes.values.any(
          (existing) => existing.authorizationId == code.authorizationId,
        )) {
      throw StateError('OAuth authorization code already exists');
    }
    while (_codes.length >= maxEntries) {
      _codes.remove(_codes.keys.first);
    }
    _codes[code.codeHash] = code;
    return code;
  }

  @override
  Future<OAuthAuthorizationCode?> consume({
    required String codeHash,
    required String clientId,
    required String redirectUri,
    required String? codeVerifier,
    DateTime? now,
  }) async {
    final consumed = _codes.remove(codeHash.trim());
    if (consumed == null || !consumed.isValid(now: now)) return null;
    if (consumed.clientId != clientId || consumed.redirectUri != redirectUri) {
      return null;
    }
    final challenge = consumed.codeChallenge;
    if (challenge == null) return consumed;
    if (consumed.codeChallengeMethod != 'S256' || codeVerifier == null) {
      return null;
    }
    final digest = sha256.convert(utf8.encode(codeVerifier));
    final expected = base64Url.encode(digest.bytes).replaceAll('=', '');
    if (!constantTimeStringEquals(expected, challenge)) return null;
    return consumed;
  }

  @override
  Future<int> deleteExpired({DateTime? now}) async {
    final current = now ?? DateTime.now().toUtc();
    final expired = _codes.entries
        .where((entry) => !entry.value.isValid(now: current))
        .map((entry) => entry.key)
        .toList();
    for (final key in expired) {
      _codes.remove(key);
    }
    return expired.length;
  }

  @override
  Future<void> deleteForUser(String userId) async {
    _codes.removeWhere((_, code) => code.userId == userId);
  }

  @override
  Future<void> deleteUserDataForDeletion(String userId) =>
      deleteForUser(userId);
}

/// In-memory access token store for tests and development.
class InMemoryOAuthAccessTokenStore
    implements OAuthAccessTokenStore, AuthInMemoryUserDeletionStore {
  final Map<String, OAuthAccessToken> _tokens = {};

  @override
  Object captureDeletionState() => Map<String, OAuthAccessToken>.of(_tokens);

  @override
  void restoreDeletionState(Object checkpoint) {
    final tokens = checkpoint as Map<String, OAuthAccessToken>;
    _tokens
      ..clear()
      ..addAll(tokens);
  }

  @override
  Future<void> save(OAuthAccessToken token) async {
    if (_tokens.containsKey(token.tokenHash) ||
        token.authorizationId != null &&
            _tokens.values.any(
              (existing) => existing.authorizationId == token.authorizationId,
            )) {
      throw StateError('OAuth access token already exists');
    }
    _tokens[token.tokenHash] = token;
  }

  @override
  Future<OAuthAccessToken?> findByToken(String token) async {
    if (token.trim().isEmpty) return null;
    return _tokens[hashOpaqueToken(token)];
  }

  @override
  Future<OAuthAccessToken?> findByRefreshToken(String refreshToken) async {
    if (refreshToken.trim().isEmpty) return null;
    final refreshTokenHash = hashOpaqueToken(refreshToken);
    for (final token in _tokens.values) {
      if (token.refreshTokenHash == refreshTokenHash) {
        return token;
      }
    }
    return null;
  }

  @override
  Future<OAuthAccessToken?> rotateRefreshToken({
    required String refreshToken,
    required String expectedTokenHash,
    required OAuthAccessToken replacement,
    int? maxUses,
  }) async {
    if (refreshToken.trim().isEmpty || expectedTokenHash.trim().isEmpty) {
      return null;
    }
    final current = _tokens[expectedTokenHash];
    if (current == null ||
        current.refreshTokenHash != hashOpaqueToken(refreshToken) ||
        !current.isRefreshTokenValid() ||
        (maxUses != null &&
            (maxUses <= 0 || current.refreshTokenUses >= maxUses))) {
      return null;
    }
    if (replacement.clientId != current.clientId ||
        replacement.userId != current.userId ||
        replacement.refreshTokenUses != current.refreshTokenUses + 1) {
      throw ArgumentError('Refresh-token replacement changed its identity.');
    }
    if (replacement.tokenHash != expectedTokenHash &&
        _tokens.containsKey(replacement.tokenHash)) {
      throw StateError('OAuth access token already exists');
    }
    _tokens.remove(expectedTokenHash);
    _tokens[replacement.tokenHash] = replacement;
    return current;
  }

  @override
  Future<void> revoke(String token) async {
    if (token.trim().isNotEmpty) _tokens.remove(hashOpaqueToken(token));
  }

  @override
  Future<int> revokeAllForUser(String userId) async {
    final tokensToRemove = _tokens.entries
        .where((entry) => entry.value.userId == userId)
        .map((entry) => entry.key)
        .toList();
    for (final key in tokensToRemove) {
      _tokens.remove(key);
    }
    return tokensToRemove.length;
  }

  @override
  Future<void> deleteUserDataForDeletion(String userId) async {
    await revokeAllForUser(userId);
  }

  @override
  Future<int> revokeAllForClient(String clientId) async {
    final tokensToRemove = _tokens.entries
        .where((entry) => entry.value.clientId == clientId)
        .map((entry) => entry.key)
        .toList();
    for (final key in tokensToRemove) {
      _tokens.remove(key);
    }
    return tokensToRemove.length;
  }

  @override
  Future<int> deleteExpired({DateTime? now}) async {
    final current = now ?? DateTime.now().toUtc();
    final expired = _tokens.entries
        .where(
          (entry) =>
              !entry.value.isValid(now: current) &&
              !entry.value.isRefreshTokenValid(now: current),
        )
        .map((entry) => entry.key)
        .toList();
    for (final key in expired) {
      _tokens.remove(key);
    }
    return expired.length;
  }
}

/// In-memory atomic authorization-code exchange store.
///
/// This adapter is intended for tests and local development. It serializes
/// exchanges and restores both maps when any fault occurs between code
/// consumption and token persistence.
final class InMemoryOAuthAuthorizationCodeExchangeStore
    implements OAuthAuthorizationCodeExchangeStore {
  InMemoryOAuthAuthorizationCodeExchangeStore({
    InMemoryOAuthAuthorizationCodeStore? authorizationCodeStore,
    InMemoryOAuthAccessTokenStore? accessTokenStore,
    this.faultInjector,
  }) : authorizationCodeStore =
           authorizationCodeStore ?? InMemoryOAuthAuthorizationCodeStore(),
       accessTokenStore = accessTokenStore ?? InMemoryOAuthAccessTokenStore();

  @override
  final InMemoryOAuthAuthorizationCodeStore authorizationCodeStore;

  @override
  final InMemoryOAuthAccessTokenStore accessTokenStore;

  final InMemoryOAuthCodeExchangeFaultInjector? faultInjector;
  Future<void> _tail = Future<void>.value();

  @override
  Future<OAuthAuthorizationCodePreparation> prepare(
    OAuthAuthorizationCodeExchangeRequest request,
  ) => _serialized(() async {
    final code = authorizationCodeStore._codes[request.codeHash.trim()];
    if (code == null) {
      return const OAuthAuthorizationCodePreparation.invalidGrant();
    }
    if (!code.isValid(now: request.now)) {
      authorizationCodeStore._codes.remove(code.codeHash);
      return const OAuthAuthorizationCodePreparation.invalidGrant();
    }
    if (!_bindingsMatch(code, request)) {
      authorizationCodeStore._codes.remove(code.codeHash);
      return const OAuthAuthorizationCodePreparation.invalidGrant();
    }
    return OAuthAuthorizationCodePreparation.ready(code);
  });

  @override
  Future<OAuthAuthorizationCodeExchangeResult> commit({
    required OAuthAuthorizationCodeExchangeRequest request,
    required String expectedAuthorizationId,
    required OAuthAccessToken preparedToken,
  }) => _serialized(() async {
    final existingToken = accessTokenStore._tokens.values
        .where(
          (token) => token.authorizationId == expectedAuthorizationId.trim(),
        )
        .firstOrNull;
    if (existingToken != null) {
      return const OAuthAuthorizationCodeExchangeResult(
        OAuthAuthorizationCodeExchangeStatus.alreadyCommitted,
      );
    }

    final codeCheckpoint = Map<String, OAuthAuthorizationCode>.of(
      authorizationCodeStore._codes,
    );
    final tokenCheckpoint = Map<String, OAuthAccessToken>.of(
      accessTokenStore._tokens,
    );
    try {
      final code = authorizationCodeStore._codes.remove(
        request.codeHash.trim(),
      );
      if (code == null ||
          !code.isValid(now: request.now) ||
          code.authorizationId != expectedAuthorizationId.trim() ||
          !_bindingsMatch(code, request)) {
        return const OAuthAuthorizationCodeExchangeResult(
          OAuthAuthorizationCodeExchangeStatus.invalidGrant,
        );
      }
      _validatePreparedToken(code, preparedToken, request.now);
      await faultInjector?.call(
        InMemoryOAuthCodeExchangeFaultPoint.afterCodeConsumption,
      );
      await accessTokenStore.save(preparedToken);
      await faultInjector?.call(
        InMemoryOAuthCodeExchangeFaultPoint.afterTokenSave,
      );
      return const OAuthAuthorizationCodeExchangeResult(
        OAuthAuthorizationCodeExchangeStatus.committed,
      );
    } catch (_) {
      authorizationCodeStore._codes
        ..clear()
        ..addAll(codeCheckpoint);
      accessTokenStore._tokens
        ..clear()
        ..addAll(tokenCheckpoint);
      rethrow;
    }
  });

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }
}

void _validateAuthorizationCode(OAuthAuthorizationCode code) {
  if (code.authorizationId.trim().isEmpty ||
      code.codeHash.trim().isEmpty ||
      code.clientId.trim().isEmpty ||
      code.userId.trim().isEmpty ||
      code.redirectUri.trim().isEmpty) {
    throw ArgumentError('Invalid OAuth authorization code');
  }
  final redirectUri = Uri.tryParse(code.redirectUri);
  if (redirectUri == null ||
      !redirectUri.isAbsolute ||
      redirectUri.hasFragment) {
    throw ArgumentError(
      'OAuth redirect URI must be absolute and fragment-free',
    );
  }
  final challenge = code.codeChallenge;
  if (challenge != null &&
      (challenge.trim().isEmpty || code.codeChallengeMethod != 'S256')) {
    throw ArgumentError('OAuth authorization codes support only S256 PKCE');
  }
  final createdAt = code.createdAt;
  if (createdAt != null && !code.expiresAt.toUtc().isAfter(createdAt.toUtc())) {
    throw ArgumentError('OAuth authorization code must not be expired');
  }
}

bool _bindingsMatch(
  OAuthAuthorizationCode code,
  OAuthAuthorizationCodeExchangeRequest request,
) {
  if (code.clientId != request.clientId.trim() ||
      code.redirectUri != request.redirectUri) {
    return false;
  }
  final challenge = code.codeChallenge;
  if (challenge == null) return true;
  final verifier = request.codeVerifier;
  if (code.codeChallengeMethod != 'S256' || verifier == null) return false;
  final digest = sha256.convert(utf8.encode(verifier));
  final expected = base64Url.encode(digest.bytes).replaceAll('=', '');
  return constantTimeStringEquals(expected, challenge);
}

void _validatePreparedToken(
  OAuthAuthorizationCode code,
  OAuthAccessToken token,
  DateTime now,
) {
  if (token.authorizationId != code.authorizationId ||
      token.tokenHash.trim().isEmpty ||
      token.clientId != code.clientId ||
      token.userId != code.userId ||
      token.scope != code.scope ||
      !token.expiresAt.toUtc().isAfter(now.toUtc()) ||
      token.refreshTokenHash?.trim().isEmpty == true) {
    throw ArgumentError('Prepared OAuth token does not match authorization.');
  }
}
