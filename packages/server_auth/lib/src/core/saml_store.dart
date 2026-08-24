import 'dart:async';

/// Persisted state for one service-provider-initiated SAML request.
final class AuthSamlAuthenticationAttempt {
  /// Creates an authentication attempt with its replay and browser bindings.
  const AuthSamlAuthenticationAttempt({
    required this.providerId,
    required this.requestId,
    required this.relayStateHash,
    required this.browserBindingHash,
    required this.callback,
    required this.createdAt,
    required this.expiresAt,
  });

  /// The SAML provider associated with the request.
  final String providerId;

  /// The request identifier sent in the SAML `InResponseTo` value.
  final String requestId;

  /// A digest of the browser-visible `RelayState` value.
  final String relayStateHash;

  /// A digest binding the request to the initiating browser context.
  final String browserBindingHash;

  /// The callback to use after successful authentication.
  final Uri callback;

  /// The time at which this attempt was created.
  final DateTime createdAt;

  /// The time after which this attempt cannot be consumed.
  final DateTime expiresAt;
}

/// Reasons why a SAML response cannot consume its authentication attempt.
enum AuthSamlConsumptionFailure {
  /// The request was absent, expired, or did not match its bindings.
  requestNotFound,

  /// The assertion identifier has already been consumed.
  assertionReplayed,

  /// The bounded replay store cannot accept another receipt.
  capacityExceeded,
}

/// Result of atomically consuming SAML request and replay state.
final class AuthSamlConsumptionResult {
  /// Creates an accepted result containing [attempt].
  const AuthSamlConsumptionResult.accepted(this.attempt) : failure = null;

  /// Creates a rejected result containing [failure].
  const AuthSamlConsumptionResult.rejected(this.failure) : attempt = null;

  /// The consumed authentication attempt, or `null` when rejected.
  final AuthSamlAuthenticationAttempt? attempt;

  /// The rejection reason, or `null` when accepted.
  final AuthSamlConsumptionFailure? failure;

  /// Whether an authentication attempt was consumed successfully.
  bool get accepted => attempt != null;
}

/// Atomic multi-instance persistence boundary for SAML request and replay state.
abstract interface class AuthSamlReplayStore {
  /// Persists a new request and rejects duplicate request identifiers.
  FutureOr<void> createAttempt(AuthSamlAuthenticationAttempt attempt);

  /// Atomically consumes one request/RelayState tuple and records assertion ID.
  FutureOr<AuthSamlConsumptionResult> consumeSpInitiated({
    required String providerId,
    required String requestId,
    required String relayStateHash,
    required String browserBindingHash,
    required String assertionId,
    required DateTime assertionExpiresAt,
    required DateTime now,
  });

  /// Atomically records an IdP-initiated assertion ID exactly once.
  FutureOr<bool> consumeIdpInitiated({
    required String providerId,
    required String assertionId,
    required DateTime assertionExpiresAt,
    required DateTime now,
  });
}

/// Marker implemented only by adapters with durable transactional guarantees.
abstract interface class AuthDurableSamlReplayStore
    implements AuthSamlReplayStore {}

/// Bounded local store for deterministic tests only.
final class InMemoryAuthSamlReplayStore implements AuthSamlReplayStore {
  /// Creates a store retaining at most [maxEntries] active records.
  ///
  /// Throws an [ArgumentError] when [maxEntries] is less than one.
  InMemoryAuthSamlReplayStore({this.maxEntries = 1024}) {
    if (maxEntries < 1) throw ArgumentError.value(maxEntries, 'maxEntries');
  }

  /// Maximum number of active attempts or assertion receipts retained.
  final int maxEntries;
  final Map<String, AuthSamlAuthenticationAttempt> _attempts = {};
  final Map<String, DateTime> _assertions = {};
  Future<void> _tail = Future<void>.value();

  /// Persists [attempt] after pruning expired state.
  @override
  Future<void> createAttempt(AuthSamlAuthenticationAttempt attempt) =>
      _atomic(() {
        _prune(attempt.createdAt);
        if (_attempts.containsKey(attempt.requestId)) {
          throw StateError('SAML request ID already exists');
        }
        if (_attempts.length >= maxEntries) {
          throw StateError('SAML attempt capacity exceeded');
        }
        _attempts[attempt.requestId] = attempt;
      });

  /// Atomically consumes a service-provider-initiated response.
  @override
  Future<AuthSamlConsumptionResult> consumeSpInitiated({
    required String providerId,
    required String requestId,
    required String relayStateHash,
    required String browserBindingHash,
    required String assertionId,
    required DateTime assertionExpiresAt,
    required DateTime now,
  }) => _atomic(() {
    _prune(now);
    final assertionKey = '$providerId\u0000$assertionId';
    if (_assertions.containsKey(assertionKey)) {
      return const AuthSamlConsumptionResult.rejected(
        AuthSamlConsumptionFailure.assertionReplayed,
      );
    }
    if (_assertions.length >= maxEntries) {
      return const AuthSamlConsumptionResult.rejected(
        AuthSamlConsumptionFailure.capacityExceeded,
      );
    }
    final attempt = _attempts[requestId];
    if (attempt == null ||
        attempt.providerId != providerId ||
        attempt.relayStateHash != relayStateHash ||
        attempt.browserBindingHash != browserBindingHash ||
        !now.toUtc().isBefore(attempt.expiresAt.toUtc())) {
      return const AuthSamlConsumptionResult.rejected(
        AuthSamlConsumptionFailure.requestNotFound,
      );
    }
    _attempts.remove(requestId);
    _assertions[assertionKey] = assertionExpiresAt.toUtc();
    return AuthSamlConsumptionResult.accepted(attempt);
  });

  /// Records an IdP-initiated assertion identifier once.
  @override
  Future<bool> consumeIdpInitiated({
    required String providerId,
    required String assertionId,
    required DateTime assertionExpiresAt,
    required DateTime now,
  }) => _atomic(() {
    _prune(now);
    final key = '$providerId\u0000$assertionId';
    if (_assertions.containsKey(key)) return false;
    if (_assertions.length >= maxEntries) return false;
    _assertions[key] = assertionExpiresAt.toUtc();
    return true;
  });

  Future<T> _atomic<T>(FutureOr<T> Function() operation) async {
    final previous = _tail;
    final complete = Completer<void>();
    _tail = complete.future;
    await previous;
    try {
      return await Future<T>.sync(operation);
    } finally {
      complete.complete();
    }
  }

  void _prune(DateTime now) {
    final current = now.toUtc();
    _attempts.removeWhere(
      (_, value) => !current.isBefore(value.expiresAt.toUtc()),
    );
    _assertions.removeWhere((_, expiresAt) => !current.isBefore(expiresAt));
  }
}
