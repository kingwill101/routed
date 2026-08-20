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
    implements OAuthAuthorizationCodeStore, AuthInMemoryTransactionParticipant {
  InMemoryOAuthAuthorizationCodeStore({this.maxEntries = 1024})
      : assert(maxEntries > 0);

  final int maxEntries;
  final Map<String, OAuthAuthorizationCode> _codes = {};

  @override
  Object createInMemoryCheckpoint() =>
      Map<String, OAuthAuthorizationCode>.of(_codes);

  @override
  void restoreInMemoryCheckpoint(Object checkpoint) {
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
    if (_codes.containsKey(code.codeHash)) {
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
}

/// In-memory access token store for tests and development.
class InMemoryOAuthAccessTokenStore
    implements OAuthAccessTokenStore, AuthInMemoryTransactionParticipant {
  final Map<String, OAuthAccessToken> _tokens = {};

  @override
  Object createInMemoryCheckpoint() =>
      Map<String, OAuthAccessToken>.of(_tokens);

  @override
  void restoreInMemoryCheckpoint(Object checkpoint) {
    final tokens = checkpoint as Map<String, OAuthAccessToken>;
    _tokens
      ..clear()
      ..addAll(tokens);
  }

  @override
  Future<void> save(OAuthAccessToken token) async {
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

void _validateAuthorizationCode(OAuthAuthorizationCode code) {
  if (code.codeHash.trim().isEmpty ||
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
        'OAuth redirect URI must be absolute and fragment-free');
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
