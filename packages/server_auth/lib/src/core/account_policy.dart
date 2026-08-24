import 'dart:async';

import 'deletion_transaction.dart';
import 'exceptions.dart';

/// Policy configuration for account states and authentication rules.
class AuthAccountPolicy {
  /// Creates an instance of AuthAccountPolicy.
  const AuthAccountPolicy({
    this.requireEmailVerification = false,
    this.allowUnverifiedSignIn = true,
    this.maxLoginAttempts = 5,
    this.lockoutDuration = const Duration(minutes: 15),
    this.disableAfterInactiveDays,
    this.allowPasswordResetForDisabled = false,
    this.allowPasswordResetForUnverified = true,
    this.requireReauthenticationForSensitiveActions = true,
    this.reauthenticationWindow = const Duration(minutes: 5),
  });

  /// Whether email verification is required before account is fully active.
  final bool requireEmailVerification;

  /// Whether unverified accounts can sign in (if false, they're blocked).
  final bool allowUnverifiedSignIn;

  /// Maximum failed login attempts before account is locked.
  final int maxLoginAttempts;

  /// Duration of account lockout after exceeding max attempts.
  final Duration lockoutDuration;

  /// Auto-disable accounts inactive for this many days (null = never).
  final int? disableAfterInactiveDays;

  /// Whether disabled accounts can use password reset.
  final bool allowPasswordResetForDisabled;

  /// Whether unverified accounts can use password reset.
  final bool allowPasswordResetForUnverified;

  /// Whether sensitive actions require recent authentication.
  final bool requireReauthenticationForSensitiveActions;

  /// Time window for reauthentication validity.
  final Duration reauthenticationWindow;

  /// Decides whether a sensitive action has an explicit recent proof.
  ///
  /// A verified password or step-up proof is authoritative. Otherwise the
  /// original authentication time must be present, not in the future, and
  /// inside [reauthenticationWindow]. Session activity does not refresh this
  /// boundary.
  bool allowsSensitiveAction({
    DateTime? authenticatedAt,
    bool passwordReauthenticated = false,
    bool stepUpVerified = false,
    DateTime? now,
  }) {
    if (!requireReauthenticationForSensitiveActions) return true;
    if (passwordReauthenticated || stepUpVerified) return true;
    if (authenticatedAt == null || reauthenticationWindow <= Duration.zero) {
      return false;
    }
    final current = (now ?? DateTime.now()).toUtc();
    final issued = authenticatedAt.toUtc();
    if (issued.isAfter(current)) return false;
    return current.difference(issued) <= reauthenticationWindow;
  }

  /// Returns safe defaults for development.
  static const AuthAccountPolicy development = AuthAccountPolicy(
    requireEmailVerification: false,
    allowUnverifiedSignIn: true,
    maxLoginAttempts: 10,
    lockoutDuration: Duration(minutes: 5),
  );

  /// Returns safe defaults for production.
  static const AuthAccountPolicy production = AuthAccountPolicy(
    requireEmailVerification: true,
    allowUnverifiedSignIn: false,
    maxLoginAttempts: 5,
    lockoutDuration: Duration(minutes: 15),
    disableAfterInactiveDays: 365,
    requireReauthenticationForSensitiveActions: true,
  );
}

/// Account state information for policy enforcement.
class AuthAccountState {
  /// Creates an instance of AuthAccountState.
  const AuthAccountState({
    required this.userId,
    this.emailVerified = false,
    this.disabled = false,
    this.disabledReason,
    this.disabledAt,
    this.lockedUntil,
    this.failedLoginAttempts = 0,
    this.lastLoginAt,
    this.lastFailedLoginAt,
    this.lastEmailVerificationSentAt,
  });

  /// User ID this state belongs to.
  final String userId;

  /// Whether the user's email has been verified.
  final bool emailVerified;

  /// Whether the account is explicitly disabled.
  final bool disabled;

  /// Reason for account disablement.
  final String? disabledReason;

  /// When the account was disabled.
  final DateTime? disabledAt;

  /// When the account lockout expires.
  final DateTime? lockedUntil;

  /// Number of consecutive failed login attempts.
  final int failedLoginAttempts;

  /// When the user last successfully logged in.
  final DateTime? lastLoginAt;

  /// When the last failed login attempt occurred.
  final DateTime? lastFailedLoginAt;

  /// When the last email verification was sent.
  final DateTime? lastEmailVerificationSentAt;

  /// Whether the account is currently locked.
  bool isLocked({DateTime? now}) {
    final current = now ?? DateTime.now().toUtc();
    return lockedUntil != null && current.isBefore(lockedUntil!);
  }

  /// Whether the account can authenticate.
  bool canAuthenticate({DateTime? now, required AuthAccountPolicy policy}) {
    if (disabled) return false;
    if (isLocked(now: now)) return false;
    if (policy.requireEmailVerification && !emailVerified) {
      return policy.allowUnverifiedSignIn;
    }
    return true;
  }

  /// Creates a copy with updated fields.
  AuthAccountState copyWith({
    bool? emailVerified,
    bool? disabled,
    String? disabledReason,
    DateTime? disabledAt,
    DateTime? lockedUntil,
    int? failedLoginAttempts,
    DateTime? lastLoginAt,
    DateTime? lastFailedLoginAt,
    DateTime? lastEmailVerificationSentAt,
    bool clearDisabled = false,
    bool clearLockedUntil = false,
    bool clearDisabledReason = false,
  }) {
    return AuthAccountState(
      userId: userId,
      emailVerified: emailVerified ?? this.emailVerified,
      disabled: clearDisabled ? false : (disabled ?? this.disabled),
      disabledReason: clearDisabledReason
          ? null
          : (disabledReason ?? this.disabledReason),
      disabledAt: clearDisabled ? null : (disabledAt ?? this.disabledAt),
      lockedUntil: clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
      failedLoginAttempts: failedLoginAttempts ?? this.failedLoginAttempts,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      lastFailedLoginAt: lastFailedLoginAt ?? this.lastFailedLoginAt,
      lastEmailVerificationSentAt:
          lastEmailVerificationSentAt ?? this.lastEmailVerificationSentAt,
    );
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'emailVerified': emailVerified,
    'disabled': disabled,
    'disabledReason': disabledReason,
    'disabledAt': disabledAt?.toUtc().toIso8601String(),
    'lockedUntil': lockedUntil?.toUtc().toIso8601String(),
    'failedLoginAttempts': failedLoginAttempts,
    'lastLoginAt': lastLoginAt?.toUtc().toIso8601String(),
    'lastFailedLoginAt': lastFailedLoginAt?.toUtc().toIso8601String(),
    'lastEmailVerificationSentAt': lastEmailVerificationSentAt
        ?.toUtc()
        .toIso8601String(),
  };

  /// Creates from JSON.
  factory AuthAccountState.fromJson(Map<String, dynamic> json) {
    return AuthAccountState(
      userId: json['userId']?.toString() ?? '',
      emailVerified: json['emailVerified'] == true,
      disabled: json['disabled'] == true,
      disabledReason: json['disabledReason']?.toString(),
      disabledAt: _parseDate(json['disabledAt']),
      lockedUntil: _parseDate(json['lockedUntil']),
      failedLoginAttempts: json['failedLoginAttempts'] as int? ?? 0,
      lastLoginAt: _parseDate(json['lastLoginAt']),
      lastFailedLoginAt: _parseDate(json['lastFailedLoginAt']),
      lastEmailVerificationSentAt: _parseDate(
        json['lastEmailVerificationSentAt'],
      ),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toUtc();
  }
}

/// Persistence contract for account state.
abstract interface class AuthAccountStateStore {
  /// Finds account state by user ID.
  FutureOr<AuthAccountState?> find(String userId);

  /// Removes all policy state belonging to [userId].
  FutureOr<void> delete(String userId);

  /// Creates or updates account state.
  FutureOr<AuthAccountState> upsert(AuthAccountState state);

  /// Records a successful login.
  FutureOr<AuthAccountState> recordLogin(String userId, {DateTime? now});

  /// Records a failed login attempt and potentially locks the account.
  FutureOr<AuthAccountState> recordFailedLogin(
    String userId, {
    required AuthAccountPolicy policy,
    DateTime? now,
  });

  /// Resets failed login attempts after successful authentication.
  FutureOr<AuthAccountState> resetFailedAttempts(
    String userId, {
    DateTime? now,
  });

  /// Marks email as verified.
  FutureOr<AuthAccountState> markEmailVerified(String userId, {DateTime? now});

  /// Disables an account.
  FutureOr<AuthAccountState> disable(
    String userId, {
    String? reason,
    DateTime? now,
  });

  /// Enables a disabled account.
  FutureOr<AuthAccountState> enable(String userId, {DateTime? now});

  /// Unlocks a locked account.
  FutureOr<AuthAccountState> unlock(String userId, {DateTime? now});

  /// Updates the last email verification sent timestamp.
  FutureOr<AuthAccountState> recordEmailVerificationSent(
    String userId, {
    DateTime? now,
  });

  /// Lists accounts that should be auto-disabled due to inactivity.
  FutureOr<List<AuthAccountState>> findInactiveAccounts({
    required int inactiveDays,
    DateTime? now,
  });
}

/// In-memory account state store for tests and development.
class InMemoryAuthAccountStateStore
    implements AuthAccountStateStore, AuthInMemoryDeletionState {
  final Map<String, AuthAccountState> _states = {};

  /// Captures deletion state.
  @override
  Object captureDeletionState() => Map<String, AuthAccountState>.of(_states);

  /// Restores deletion state.
  @override
  void restoreDeletionState(Object state) {
    _states
      ..clear()
      ..addAll(state as Map<String, AuthAccountState>);
  }

  /// Looks up the requested value.
  @override
  Future<AuthAccountState?> find(String userId) async {
    return _states[userId.trim()];
  }

  /// Deletes the requested value.
  @override
  Future<void> delete(String userId) async {
    _states.remove(userId.trim());
  }

  /// Creates or updates the stored value.
  @override
  Future<AuthAccountState> upsert(AuthAccountState state) async {
    final userId = state.userId.trim();
    _states[userId] = state;
    return state;
  }

  /// Records login.
  @override
  Future<AuthAccountState> recordLogin(String userId, {DateTime? now}) async {
    final current = now ?? DateTime.now().toUtc();
    final existing =
        _states[userId.trim()] ?? AuthAccountState(userId: userId.trim());
    final updated = existing.copyWith(
      lastLoginAt: current,
      failedLoginAttempts: 0,
      clearLockedUntil: true,
    );
    _states[userId.trim()] = updated;
    return updated;
  }

  /// Records failed login.
  @override
  Future<AuthAccountState> recordFailedLogin(
    String userId, {
    required AuthAccountPolicy policy,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now().toUtc();
    final existing =
        _states[userId.trim()] ?? AuthAccountState(userId: userId.trim());
    final attempts = existing.failedLoginAttempts + 1;
    DateTime? lockedUntil;
    if (attempts >= policy.maxLoginAttempts) {
      lockedUntil = current.add(policy.lockoutDuration);
    }
    final updated = existing.copyWith(
      failedLoginAttempts: attempts,
      lastFailedLoginAt: current,
      lockedUntil: lockedUntil,
    );
    _states[userId.trim()] = updated;
    return updated;
  }

  /// Resets failed attempts.
  @override
  Future<AuthAccountState> resetFailedAttempts(
    String userId, {
    DateTime? now,
  }) async {
    final existing =
        _states[userId.trim()] ?? AuthAccountState(userId: userId.trim());
    final updated = existing.copyWith(
      failedLoginAttempts: 0,
      clearLockedUntil: true,
    );
    _states[userId.trim()] = updated;
    return updated;
  }

  /// Records email verified.
  @override
  Future<AuthAccountState> markEmailVerified(
    String userId, {
    DateTime? now,
  }) async {
    final existing =
        _states[userId.trim()] ?? AuthAccountState(userId: userId.trim());
    final updated = existing.copyWith(emailVerified: true);
    _states[userId.trim()] = updated;
    return updated;
  }

  /// Disables the account.
  @override
  Future<AuthAccountState> disable(
    String userId, {
    String? reason,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now().toUtc();
    final existing =
        _states[userId.trim()] ?? AuthAccountState(userId: userId.trim());
    final updated = existing.copyWith(
      disabled: true,
      disabledReason: reason,
      disabledAt: current,
    );
    _states[userId.trim()] = updated;
    return updated;
  }

  /// Enables the account.
  @override
  Future<AuthAccountState> enable(String userId, {DateTime? now}) async {
    final existing =
        _states[userId.trim()] ?? AuthAccountState(userId: userId.trim());
    final updated = existing.copyWith(clearDisabled: true);
    _states[userId.trim()] = updated;
    return updated;
  }

  /// Unlocks the account.
  @override
  Future<AuthAccountState> unlock(String userId, {DateTime? now}) async {
    final existing =
        _states[userId.trim()] ?? AuthAccountState(userId: userId.trim());
    final updated = existing.copyWith(clearLockedUntil: true);
    _states[userId.trim()] = updated;
    return updated;
  }

  /// Records email verification sent.
  @override
  Future<AuthAccountState> recordEmailVerificationSent(
    String userId, {
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now().toUtc();
    final existing =
        _states[userId.trim()] ?? AuthAccountState(userId: userId.trim());
    final updated = existing.copyWith(lastEmailVerificationSentAt: current);
    _states[userId.trim()] = updated;
    return updated;
  }

  /// Looks up inactive accounts.
  @override
  Future<List<AuthAccountState>> findInactiveAccounts({
    required int inactiveDays,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now().toUtc();
    final cutoff = current.subtract(Duration(days: inactiveDays));
    return _states.values.where((state) {
      if (state.disabled) return false;
      if (state.lastLoginAt == null) return true;
      return state.lastLoginAt!.isBefore(cutoff);
    }).toList();
  }
}

/// Validates that an account can authenticate under the current policy.
///
/// Throws [AuthFlowException] if authentication is not allowed.
Future<void> enforceAccountPolicy({
  required AuthAccountStateStore accountStateStore,
  required AuthAccountPolicy policy,
  required String userId,
  DateTime? now,
}) async {
  final state = await accountStateStore.find(userId);
  if (state == null) {
    // No state means fresh account, allow
    return;
  }

  if (state.disabled) {
    throw AuthFlowException('account_disabled');
  }

  if (state.isLocked(now: now)) {
    throw AuthFlowException('account_locked');
  }

  if (policy.requireEmailVerification && !state.emailVerified) {
    if (!policy.allowUnverifiedSignIn) {
      throw AuthFlowException('email_not_verified');
    }
  }
}

/// Records a successful login and resets failure counters.
Future<AuthAccountState> recordSuccessfulLogin({
  required AuthAccountStateStore accountStateStore,
  required String userId,
  DateTime? now,
}) async {
  return accountStateStore.recordLogin(userId, now: now);
}

/// Records a failed login attempt and potentially locks the account.
Future<AuthAccountState> recordFailedLoginAttempt({
  required AuthAccountStateStore accountStateStore,
  required AuthAccountPolicy policy,
  required String userId,
  DateTime? now,
}) async {
  return accountStateStore.recordFailedLogin(userId, policy: policy, now: now);
}
