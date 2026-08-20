import 'dart:async';

final class AuthSamlAuthenticationAttempt {
  const AuthSamlAuthenticationAttempt({
    required this.providerId,
    required this.requestId,
    required this.relayStateHash,
    required this.browserBindingHash,
    required this.callback,
    required this.createdAt,
    required this.expiresAt,
  });

  final String providerId;
  final String requestId;
  final String relayStateHash;
  final String browserBindingHash;
  final Uri callback;
  final DateTime createdAt;
  final DateTime expiresAt;
}

enum AuthSamlConsumptionFailure {
  requestNotFound,
  assertionReplayed,
  capacityExceeded,
}

final class AuthSamlConsumptionResult {
  const AuthSamlConsumptionResult.accepted(this.attempt) : failure = null;
  const AuthSamlConsumptionResult.rejected(this.failure) : attempt = null;

  final AuthSamlAuthenticationAttempt? attempt;
  final AuthSamlConsumptionFailure? failure;
  bool get accepted => attempt != null;
}

/// Atomic multi-instance persistence boundary for SAML request and replay state.
abstract interface class AuthSamlReplayStore {
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
  InMemoryAuthSamlReplayStore({this.maxEntries = 1024}) {
    if (maxEntries < 1) throw ArgumentError.value(maxEntries, 'maxEntries');
  }

  final int maxEntries;
  final Map<String, AuthSamlAuthenticationAttempt> _attempts = {};
  final Map<String, DateTime> _assertions = {};
  Future<void> _tail = Future<void>.value();

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
