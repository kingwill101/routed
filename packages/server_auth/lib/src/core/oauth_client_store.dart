import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
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
  /// Saves an authorization code.
  FutureOr<void> save(OAuthAuthorizationCode code);

  /// Consumes an authorization code (one-time use).
  FutureOr<OAuthAuthorizationCode?> consume(String code);

  /// Deletes expired codes.
  FutureOr<int> deleteExpired({DateTime? now});
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
    implements OAuthAuthorizationCodeStore {
  final Map<String, OAuthAuthorizationCode> _codes = {};

  @override
  Future<void> save(OAuthAuthorizationCode code) async {
    _codes[code.code] = code;
  }

  @override
  Future<OAuthAuthorizationCode?> consume(String code) async {
    final consumed = _codes.remove(code);
    if (consumed == null) return null;
    if (!consumed.isValid()) return null;
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
}

/// In-memory access token store for tests and development.
class InMemoryOAuthAccessTokenStore implements OAuthAccessTokenStore {
  final Map<String, OAuthAccessToken> _tokens = {};

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
