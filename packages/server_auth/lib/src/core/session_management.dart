import 'models.dart';
import 'store.dart';

/// Safe public projection of a persisted server-side session.
///
/// The token digest is intentionally excluded. Applications can use this
/// model to build a session/security-management screen without exposing a
/// credential that could authenticate a request.
class AuthSessionInfo {
  /// Creates a redacted projection from persisted session fields.
  ///
  /// The token digest is never retained. Set [isCurrent] when the record is
  /// the session represented by the caller's current credential.
  const AuthSessionInfo({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.expiresAt,
    required this.lastUsedAt,
    required this.authenticationMethod,
    required this.isCurrent,
    this.revokedAt,
    this.ipAddress,
    this.userAgent,
  });

  /// Persisted session record identifier.
  final String id;

  /// Identifier of the user who owns the session.
  final String userId;

  /// Time at which the session was created.
  final DateTime createdAt;

  /// Time at which the session expires.
  final DateTime expiresAt;

  /// Most recent time at which the session was used.
  final DateTime lastUsedAt;

  /// Revocation time, or null when the session has not been revoked.
  final DateTime? revokedAt;

  /// Optional source IP address recorded for the session.
  final String? ipAddress;

  /// Optional user-agent string recorded for the session.
  final String? userAgent;

  /// Authentication mechanism that created the session.
  final String authenticationMethod;

  /// Whether this record matches the caller's current session.
  final bool isCurrent;

  /// Returns whether this session is not revoked and has not expired.
  ///
  /// The comparison uses UTC and the current wall clock unless [now] is
  /// supplied. Expiration is strict: a session at its expiry instant is
  /// inactive.
  bool isActive({DateTime? now}) {
    return revokedAt == null &&
        (now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());
  }

  /// Creates a safe projection from [record].
  ///
  /// Copies public session metadata from [record], excludes its token digest,
  /// and defaults [isCurrent] to false.
  factory AuthSessionInfo.fromRecord(
    AuthSessionRecord record, {
    bool isCurrent = false,
  }) {
    return AuthSessionInfo(
      id: record.id,
      userId: record.userId,
      createdAt: record.createdAt,
      expiresAt: record.expiresAt,
      lastUsedAt: record.lastUsedAt,
      revokedAt: record.revokedAt,
      ipAddress: record.ipAddress,
      userAgent: record.userAgent,
      authenticationMethod: record.authenticationMethod,
      isCurrent: isCurrent,
    );
  }

  /// Converts this projection to a JSON-compatible map.
  ///
  /// The output omits credential digests and computes `active` using the
  /// current wall clock rather than a caller-provided filtering time.
  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'lastUsedAt': lastUsedAt.toUtc().toIso8601String(),
    'revokedAt': revokedAt?.toUtc().toIso8601String(),
    'ipAddress': ipAddress,
    'userAgent': userAgent,
    'authenticationMethod': authenticationMethod,
    'isCurrent': isCurrent,
    'active': isActive(),
  };
}

/// Lists active sessions for a user, placing the current session first.
///
/// Trims [userId] and returns an empty list for blank input. Records are
/// filtered using [now] (or the current UTC time), projected without token
/// digests, and then ordered by current-session status followed by descending
/// [AuthSessionInfo.lastUsedAt].
Future<List<AuthSessionInfo>> listAuthSessionsForUser({
  required AuthStore store,
  required String userId,
  String? currentSessionId,
  DateTime? now,
}) async {
  final normalizedUserId = userId.trim();
  if (normalizedUserId.isEmpty) return const <AuthSessionInfo>[];
  final current = (now ?? DateTime.now()).toUtc();
  final records = await Future.sync(
    () => store.sessions.listForUser(normalizedUserId),
  );
  final sessions = records
      .where((record) => record.isActive(now: current))
      .map(
        (record) => AuthSessionInfo.fromRecord(
          record,
          isCurrent: record.id == currentSessionId,
        ),
      )
      .toList();
  sessions.sort((left, right) {
    if (left.isCurrent != right.isCurrent) return left.isCurrent ? -1 : 1;
    return right.lastUsedAt.compareTo(left.lastUsedAt);
  });
  return sessions;
}
