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

/// Bindings presented during an authorization-code exchange.
final class OAuthAuthorizationCodeExchangeRequest {
  /// Creates the digest-only bindings for an authorization-code exchange.
  ///
  /// [codeHash], [clientId], and [redirectUri] identify the one-time grant;
  /// [codeVerifier] supplies its raw optional PKCE proof and [now] fixes the
  /// validity-check timestamp. The raw verifier is transient and is not a
  /// persistence key.
  const OAuthAuthorizationCodeExchangeRequest({
    required this.codeHash,
    required this.clientId,
    required this.redirectUri,
    required this.codeVerifier,
    required this.now,
  });

  /// Digest of the one-time authorization code.
  final String codeHash;

  /// OAuth client identifier bound to the authorization code.
  final String clientId;

  /// Exact redirect URI bound to the authorization code.
  final String redirectUri;

  /// Optional PKCE verifier supplied by the token client.
  final String? codeVerifier;

  /// UTC time used for expiry and validity checks.
  final DateTime now;
}

/// Result of checking exchange bindings without consuming a valid code.
///
/// A store must consume a matching code digest when any supplied binding is
/// wrong. A ready result remains subject to the atomic `commit` comparison.
enum OAuthAuthorizationCodePreparationStatus {
  /// The code passed binding checks and is ready for commit.
  ready,

  /// The code is missing, expired, or failed a binding check.
  invalidGrant,
}

/// Result of preparing an authorization-code exchange.
final class OAuthAuthorizationCodePreparation {
  /// Creates a preparation result with [status] and optional authorization.
  const OAuthAuthorizationCodePreparation._(this.status, this.authorization);

  /// Creates a successful result containing the persisted authorization.
  const OAuthAuthorizationCodePreparation.ready(
    OAuthAuthorizationCode authorization,
  ) : this._(OAuthAuthorizationCodePreparationStatus.ready, authorization);

  /// Creates a failed result without revealing persisted authorization data.
  const OAuthAuthorizationCodePreparation.invalidGrant()
    : this._(OAuthAuthorizationCodePreparationStatus.invalidGrant, null);

  /// Outcome of preparation.
  final OAuthAuthorizationCodePreparationStatus status;

  /// Persisted authorization when preparation succeeded.
  final OAuthAuthorizationCode? authorization;
}

/// Result of the backend-owned code-consumption and token-persistence commit.
enum OAuthAuthorizationCodeExchangeStatus {
  /// The code was consumed and the token was persisted.
  committed,

  /// The code or one of its exchange bindings was invalid.
  invalidGrant,

  /// Another exchange already committed the same authorization ID.
  alreadyCommitted,
}

/// Atomic authorization-code exchange result.
///
/// No result contains raw code or token material. The
/// [OAuthAuthorizationCodeExchangeStatus.alreadyCommitted] result tells the
/// caller that a previous request won, but does not promise response replay.
final class OAuthAuthorizationCodeExchangeResult {
  /// Creates an exchange result with [status].
  const OAuthAuthorizationCodeExchangeResult(this.status);

  /// Atomic outcome of the exchange.
  final OAuthAuthorizationCodeExchangeStatus status;
}

/// Authoritative persistence capability for authorization-code grants.
///
/// Implementations own the authorization-code and access-token stores used by
/// provider mode. The `commit` operation must atomically:
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
  /// Authorization-code store owned by this exchange backend.
  ///
  /// It must share the transaction and persistence topology of
  /// [accessTokenStore].
  OAuthAuthorizationCodeStore get authorizationCodeStore;

  /// Access-token store owned by this exchange backend.
  ///
  /// It must share the transaction and persistence topology of
  /// [authorizationCodeStore].
  OAuthAccessTokenStore get accessTokenStore;

  /// Checks bindings and returns the persisted authorization needed to prepare
  /// token digests and an OIDC ID token before commit.
  ///
  /// A code with a matching digest but wrong binding is consumed. A correctly
  /// bound code is not consumed until `commit`, allowing account and client
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
  /// Runs after code removal and before token persistence.
  afterCodeConsumption,

  /// Runs after token persistence, before the exchange returns.
  afterTokenSave,
}

/// Callback used to inject a one-shot exchange failure in tests.
typedef InMemoryOAuthCodeExchangeFaultInjector =
    FutureOr<void> Function(InMemoryOAuthCodeExchangeFaultPoint point);

/// In-memory OAuth client store for tests and development.
class InMemoryOAuthClientStore implements OAuthClientStore {
  final Map<String, OAuthClient> _clients = {};

  /// Looks up [clientId] after trimming it; returns null when absent.
  @override
  Future<OAuthClient?> findById(String clientId) async {
    return _clients[clientId.trim()];
  }

  /// Returns an unmodifiable snapshot of all registered clients.
  @override
  Future<List<OAuthClient>> listAll() async {
    return List.unmodifiable(_clients.values);
  }

  /// Stores [client], throwing [StateError] when its ID already exists.
  ///
  /// Client IDs are used as supplied; this adapter does not normalize them
  /// during creation.
  @override
  Future<OAuthClient> create(OAuthClient client) async {
    if (_clients.containsKey(client.clientId)) {
      throw StateError('Client already exists');
    }
    _clients[client.clientId] = client;
    return client;
  }

  /// Replaces an existing client, throwing [StateError] when it is absent.
  @override
  Future<OAuthClient> update(OAuthClient client) async {
    if (!_clients.containsKey(client.clientId)) {
      throw StateError('Client not found');
    }
    _clients[client.clientId] = client;
    return client;
  }

  /// Deletes [clientId] after trimming it; missing IDs are ignored.
  @override
  Future<void> delete(String clientId) async {
    _clients.remove(clientId.trim());
  }

  /// Validates [secret] against the stored SHA-256 digest in constant time.
  ///
  /// A missing client or blank secret returns false. The raw secret is never
  /// persisted by this adapter.
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
  /// Creates a bounded code store with [maxEntries] positive.
  ///
  /// Expired records are pruned on creation and the oldest insertion is
  /// evicted when capacity is reached.
  InMemoryOAuthAuthorizationCodeStore({this.maxEntries = 1024})
    : assert(maxEntries > 0);

  /// Maximum number of unconsumed authorization codes retained.
  final int maxEntries;
  final Map<String, OAuthAuthorizationCode> _codes = {};

  /// Captures a copy of the code map for deletion rollback.
  ///
  /// The returned checkpoint is intended for the deletion coordinator and
  /// should be restored only through [restoreDeletionState].
  @override
  Object captureDeletionState() =>
      Map<String, OAuthAuthorizationCode>.of(_codes);

  /// Restores a checkpoint created by [captureDeletionState].
  @override
  void restoreDeletionState(Object checkpoint) {
    final codes = checkpoint as Map<String, OAuthAuthorizationCode>;
    _codes
      ..clear()
      ..addAll(codes);
  }

  /// Validates and stores [code], retaining only its supplied digest.
  ///
  /// Blank identifiers, invalid redirect or PKCE settings, expired creation
  /// metadata, duplicate code hashes, and duplicate authorization IDs throw.
  /// Expired entries are pruned and the oldest entry is evicted at capacity.
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

  /// Consumes a code digest at most once after checking all bindings.
  ///
  /// The matching record is removed before expiry, client, redirect, or PKCE
  /// checks, so a wrong binding burns the code. PKCE uses S256 and a
  /// constant-time comparison.
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

  /// Removes and counts codes that are expired at [now].
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

  /// Deletes unconsumed codes whose user ID exactly equals [userId].
  @override
  Future<void> deleteForUser(String userId) async {
    _codes.removeWhere((_, code) => code.userId == userId);
  }

  /// Deletes this user's authorization-code data for account deletion.
  @override
  Future<void> deleteUserDataForDeletion(String userId) =>
      deleteForUser(userId);
}

/// In-memory access token store for tests and development.
class InMemoryOAuthAccessTokenStore
    implements OAuthAccessTokenStore, AuthInMemoryUserDeletionStore {
  final Map<String, OAuthAccessToken> _tokens = {};

  /// Captures a copy of the token map for deletion rollback.
  ///
  /// The returned checkpoint is intended for the deletion coordinator and
  /// should be restored only through [restoreDeletionState].
  @override
  Object captureDeletionState() => Map<String, OAuthAccessToken>.of(_tokens);

  /// Restores a checkpoint created by [captureDeletionState].
  @override
  void restoreDeletionState(Object checkpoint) {
    final tokens = checkpoint as Map<String, OAuthAccessToken>;
    _tokens
      ..clear()
      ..addAll(tokens);
  }

  /// Saves [token] by digest, rejecting duplicate token hashes or
  /// authorization IDs.
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

  /// Finds a token by hashing [token]; blank input returns null.
  @override
  Future<OAuthAccessToken?> findByToken(String token) async {
    if (token.trim().isEmpty) return null;
    return _tokens[hashOpaqueToken(token)];
  }

  /// Finds a token by its raw refresh-token value; blank input returns null.
  ///
  /// The value is hashed internally and is never used as a storage key.
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

  /// Atomically replaces a valid refresh-token record with [replacement].
  ///
  /// The expected access-token hash, refresh-token digest, lifetime, use limit,
  /// client, user, and incremented use count must all match. A failed check
  /// returns null; an invalid replacement identity throws [ArgumentError].
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

  /// Revokes the token represented by [token]; blank input is ignored.
  @override
  Future<void> revoke(String token) async {
    if (token.trim().isNotEmpty) _tokens.remove(hashOpaqueToken(token));
  }

  /// Revokes and counts all tokens owned by [userId].
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

  /// Revokes this user's token data for account deletion.
  @override
  Future<void> deleteUserDataForDeletion(String userId) async {
    await revokeAllForUser(userId);
  }

  /// Revokes and counts all tokens issued to [clientId].
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

  /// Removes and counts tokens whose access and refresh lifetimes have ended.
  ///
  /// A record is retained while its refresh token remains valid.
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
  /// Creates a process-local serialized exchange store.
  ///
  /// When stores are omitted, bounded in-memory code and token stores are
  /// created. [faultInjector] is intended to exercise rollback paths.
  InMemoryOAuthAuthorizationCodeExchangeStore({
    InMemoryOAuthAuthorizationCodeStore? authorizationCodeStore,
    InMemoryOAuthAccessTokenStore? accessTokenStore,
    this.faultInjector,
  }) : authorizationCodeStore =
           authorizationCodeStore ?? InMemoryOAuthAuthorizationCodeStore(),
       accessTokenStore = accessTokenStore ?? InMemoryOAuthAccessTokenStore();

  /// Code store participating in the serialized exchange.
  @override
  final InMemoryOAuthAuthorizationCodeStore authorizationCodeStore;

  /// Access-token store participating in the serialized exchange.
  @override
  final InMemoryOAuthAccessTokenStore accessTokenStore;

  /// Optional callback for injecting rollback-test failures.
  final InMemoryOAuthCodeExchangeFaultInjector? faultInjector;
  Future<void> _tail = Future<void>.value();

  /// Checks a code without consuming a correctly bound record.
  ///
  /// Missing, expired, or mismatched records are removed and return
  /// [OAuthAuthorizationCodePreparationStatus.invalidGrant].
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

  /// Atomically consumes the prepared code and saves its token.
  ///
  /// Calls are serialized, authorization and binding identities are rechecked,
  /// and snapshots restore both stores if validation, injection, or token
  /// persistence fails. A previously committed authorization returns
  /// [OAuthAuthorizationCodeExchangeStatus.alreadyCommitted].
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
