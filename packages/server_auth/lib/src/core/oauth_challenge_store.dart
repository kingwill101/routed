import 'dart:async';

import 'tokens.dart' show hashOpaqueToken;

/// The short-lived values required to finish one OAuth authorization attempt.
///
/// The state value is the one-time challenge sent to the provider and
/// returned by its callback.
/// Persistent implementations must protect [codeVerifier], [nonce], and
/// [callbackUrl] appropriately and make [AuthOAuthChallengeStore.consume] an
/// atomic delete-and-return operation.
class AuthOAuthChallenge {
  /// Creates the short-lived values associated with one OAuth attempt.
  ///
  /// [state] is the raw one-time callback secret generated for the attempt.
  /// Persisted implementations must hash it before using it as a lookup key
  /// and protect the other challenge fields.
  const AuthOAuthChallenge({
    required this.providerId,
    required this.state,
    required this.expiresAt,
    this.codeVerifier,
    this.nonce,
    this.callbackUrl,
  });

  /// OAuth provider identifier used to partition callback challenges.
  final String providerId;

  /// Raw one-time state returned by the provider callback.
  final String state;

  /// Optional proof used by the provider's code exchange.
  final String? codeVerifier;

  /// Optional nonce used to bind the provider response to this attempt.
  final String? nonce;

  /// Optional callback URL to use after the authorization attempt completes.
  final String? callbackUrl;

  /// UTC time after which this challenge cannot be consumed.
  final DateTime expiresAt;

  /// Whether this challenge is active at [now].
  ///
  /// The comparison is strict: [now] must be before [expiresAt]. This check
  /// does not consume or modify the challenge.
  bool isActive({DateTime? now}) =>
      (now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());
}

/// Persistence boundary for one-time OAuth authorization challenges.
abstract interface class AuthOAuthChallengeStore {
  /// Persists [challenge] for one authorization attempt.
  ///
  /// Implementations should reject invalid or expired challenges and protect
  /// all secret fields. Durable implementations should hash [state] for
  /// lookup rather than using it as a persistence key; an in-memory store may
  /// retain the challenge fields for the lifetime of the process.
  FutureOr<void> save(AuthOAuthChallenge challenge);

  /// Atomically consumes a matching, unexpired challenge.
  ///
  /// At most one concurrent caller may receive a challenge. Implementations
  /// must not use the raw state as a persistence key; [state] is only the
  /// lookup secret supplied by the callback request.
  FutureOr<AuthOAuthChallenge?> consume(String providerId, String state);
}

/// In-memory OAuth challenge store for tests and local development.
///
/// State keys are hashed, while the challenge fields remain in process memory
/// until consumed or evicted.
class InMemoryAuthOAuthChallengeStore implements AuthOAuthChallengeStore {
  /// Creates a bounded store using [clock] for expiry checks.
  ///
  /// [maxEntries] must be positive. The store hashes state keys, prunes
  /// expired entries on save, replaces an existing provider/state pair, and
  /// evicts the oldest entry when full.
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

  /// Saves an active [challenge] under its hashed provider/state key.
  ///
  /// Exact empty provider IDs or states throw an [ArgumentError], as does an
  /// expired challenge. Existing entries with the same key are replaced before
  /// expired-entry pruning and capacity eviction.
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

  /// Atomically consumes a matching active challenge at most once.
  ///
  /// The hashed key is removed before expiry is checked, so expired challenges
  /// cannot be replayed. Exact empty provider IDs or states return null.
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
