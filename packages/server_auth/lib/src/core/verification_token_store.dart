import 'dart:async';

import 'models.dart' show AuthVerificationToken;
import 'tokens.dart' show hashOpaqueToken;

/// Storage interface used by email magic-link verification flows.
///
/// Implementations must make [consume] a single atomic operation: at most one
/// concurrent caller may receive a matching, unexpired token. Persistent
/// implementations should store only a digest of the token, never the raw
/// value sent to the user.
abstract class AuthVerificationTokenStore {
  FutureOr<void> save(AuthVerificationToken token);

  FutureOr<AuthVerificationToken?> consume(String identifier, String token);

  FutureOr<void> delete(String identifier);
}

/// In-memory token store for development and tests.
class InMemoryAuthVerificationTokenStore implements AuthVerificationTokenStore {
  InMemoryAuthVerificationTokenStore({
    DateTime Function()? clock,
    this.maxTokens = 1024,
  }) : _clock = clock ?? DateTime.now {
    if (maxTokens < 1) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be positive');
    }
  }

  final Map<String, Map<String, DateTime>> _tokens =
      <String, Map<String, DateTime>>{};
  final DateTime Function() _clock;

  /// Maximum number of token digests retained by this local store.
  ///
  /// Expired digests are removed when a token is saved or consumed. If the
  /// store is full, the oldest digest is evicted before a new one is added.
  /// Durable stores should enforce equivalent expiry and capacity policies.
  final int maxTokens;

  @override
  Future<void> save(AuthVerificationToken token) async {
    if (token.identifier.isEmpty) {
      throw ArgumentError.value(token.identifier, 'identifier');
    }
    if (token.token.isEmpty) {
      throw ArgumentError.value(token.token, 'token');
    }
    final now = _clock();
    _removeExpired(now);
    if (!now.isBefore(token.expiresAt)) {
      return;
    }
    final digest = hashOpaqueToken(token.token);
    final byDigest = _tokens.putIfAbsent(
      token.identifier,
      () => <String, DateTime>{},
    );
    final alreadyStored = byDigest.containsKey(digest);
    if (!alreadyStored) {
      while (_tokenCount >= maxTokens) {
        _removeOldest();
      }
    }
    byDigest[digest] = token.expiresAt;
  }

  @override
  Future<AuthVerificationToken?> consume(
    String identifier,
    String token,
  ) async {
    if (identifier.isEmpty || token.isEmpty) {
      return null;
    }
    final now = _clock();
    _removeExpired(now);
    final byDigest = _tokens[identifier];
    if (byDigest == null) {
      return null;
    }
    final expiresAt = byDigest.remove(hashOpaqueToken(token));
    if (byDigest.isEmpty) {
      _tokens.remove(identifier);
    }
    if (expiresAt == null || !now.isBefore(expiresAt)) {
      return null;
    }
    return AuthVerificationToken(
      identifier: identifier,
      token: token,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<void> delete(String identifier) async {
    _tokens.remove(identifier);
  }

  int get _tokenCount =>
      _tokens.values.fold<int>(0, (count, tokens) => count + tokens.length);

  void _removeExpired(DateTime now) {
    _tokens.removeWhere((_, tokens) {
      tokens.removeWhere((_, expiresAt) => !now.isBefore(expiresAt));
      return tokens.isEmpty;
    });
  }

  void _removeOldest() {
    if (_tokens.isEmpty) return;
    final identifier = _tokens.keys.firstWhere(
      (key) => _tokens[key]!.isNotEmpty,
    );
    final tokens = _tokens[identifier]!;
    tokens.remove(tokens.keys.first);
    if (tokens.isEmpty) _tokens.remove(identifier);
  }
}
