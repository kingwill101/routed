import 'dart:async';

import 'tokens.dart' show hashOpaqueToken;

/// The short-lived values required to finish one OAuth authorization attempt.
///
/// The state value is the one-time bearer challenge returned to the provider.
/// Persistent implementations must protect [codeVerifier], [nonce], and
/// [callbackUrl] appropriately and make [AuthOAuthChallengeStore.consume] an
/// atomic delete-and-return operation.
class AuthOAuthChallenge {
  const AuthOAuthChallenge({
    required this.providerId,
    required this.state,
    required this.expiresAt,
    this.codeVerifier,
    this.nonce,
    this.callbackUrl,
  });

  final String providerId;
  final String state;
  final String? codeVerifier;
  final String? nonce;
  final String? callbackUrl;
  final DateTime expiresAt;

  bool isActive({DateTime? now}) =>
      (now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());
}

/// Persistence boundary for one-time OAuth authorization challenges.
abstract interface class AuthOAuthChallengeStore {
  FutureOr<void> save(AuthOAuthChallenge challenge);

  /// Atomically consumes a matching, unexpired challenge.
  ///
  /// At most one concurrent caller may receive a challenge. Implementations
  /// must not use the raw state as a persistence key; [state] is only the
  /// lookup secret supplied by the callback request.
  FutureOr<AuthOAuthChallenge?> consume(String providerId, String state);
}

/// In-memory OAuth challenge store for tests and local development.
class InMemoryAuthOAuthChallengeStore implements AuthOAuthChallengeStore {
  InMemoryAuthOAuthChallengeStore({
    DateTime Function()? clock,
    this.maxEntries = 1024,
  }) : _clock = clock ?? DateTime.now {
    if (maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
  }

  final Map<String, AuthOAuthChallenge> _challenges =
      <String, AuthOAuthChallenge>{};
  final DateTime Function() _clock;

  /// Maximum number of unconsumed challenges retained by this local store.
  ///
  /// Expired entries are removed whenever a new challenge is saved. If the
  /// store is full, the oldest unconsumed entry is evicted. Durable stores
  /// should enforce equivalent expiry and capacity policies in persistence.
  final int maxEntries;

  @override
  Future<void> save(AuthOAuthChallenge challenge) async {
    if (challenge.providerId.isEmpty) {
      throw ArgumentError.value(challenge.providerId, 'providerId');
    }
    if (challenge.state.isEmpty) {
      throw ArgumentError.value(challenge.state, 'state');
    }
    final now = _clock();
    if (!challenge.isActive(now: now)) {
      throw ArgumentError.value(challenge.expiresAt, 'expiresAt');
    }
    final key = _key(challenge.providerId, challenge.state);
    _challenges.remove(key);
    _challenges.removeWhere((_, existing) => !existing.isActive(now: now));
    while (_challenges.length >= maxEntries) {
      _challenges.remove(_challenges.keys.first);
    }
    _challenges[key] = challenge;
  }

  @override
  Future<AuthOAuthChallenge?> consume(String providerId, String state) async {
    if (providerId.isEmpty || state.isEmpty) {
      return null;
    }
    final now = _clock();
    final challenge = _challenges.remove(_key(providerId, state));
    if (challenge == null || !challenge.isActive(now: now)) {
      return null;
    }
    return challenge;
  }

  String _key(String providerId, String state) {
    return '$providerId:${hashOpaqueToken(state)}';
  }
}
