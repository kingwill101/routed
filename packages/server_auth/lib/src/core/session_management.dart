import 'models.dart';
import 'store.dart';

/// Safe public projection of a persisted server-side session.
///
/// The token digest is intentionally excluded. Applications can use this
/// model to build a session/security-management screen without exposing a
/// credential that could authenticate a request.
class AuthSessionInfo {
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

  final String id;
  final String userId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime lastUsedAt;
  final DateTime? revokedAt;
  final String? ipAddress;
  final String? userAgent;
  final String authenticationMethod;
  final bool isCurrent;

  bool isActive({DateTime? now}) {
    return revokedAt == null &&
        (now ?? DateTime.now()).toUtc().isBefore(expiresAt.toUtc());
  }

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

/// Lists active sessions for a user, newest activity first.
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
