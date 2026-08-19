import 'dart:async';

import 'models.dart';
import 'users.dart' show normalizeAuthEmail;

List<String> normalizeAuthAdminRoles(Iterable<String> roles) =>
    List<String>.unmodifiable(
      roles
          .map((role) => role.trim().toLowerCase())
          .where((role) => role.isNotEmpty)
          .toSet()
          .toList()
        ..sort(),
    );

Map<String, dynamic> sanitizeAuthAdminAttributes(Map<String, dynamic>? value) =>
    sanitizeAuthPublicAttributes(value ?? const <String, dynamic>{});

final class AuthAdminUserState {
  AuthAdminUserState({
    required this.userId,
    this.banned = false,
    this.banReason,
    DateTime? banExpiresAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : banExpiresAt = banExpiresAt?.toUtc(),
       createdAt = (createdAt ?? DateTime.now()).toUtc(),
       updatedAt = (updatedAt ?? DateTime.now()).toUtc();

  final String userId;
  final bool banned;
  final String? banReason;
  final DateTime? banExpiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool isBanned({DateTime? now}) =>
      banned &&
      (banExpiresAt == null ||
          (now ?? DateTime.now()).toUtc().isBefore(banExpiresAt!));

  AuthAdminUserState copyWith({
    bool? banned,
    String? banReason,
    DateTime? banExpiresAt,
    bool clearBanReason = false,
    bool clearBanExpiresAt = false,
    DateTime? updatedAt,
  }) => AuthAdminUserState(
    userId: userId,
    banned: banned ?? this.banned,
    banReason: clearBanReason ? null : banReason ?? this.banReason,
    banExpiresAt: clearBanExpiresAt ? null : banExpiresAt ?? this.banExpiresAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'banned': isBanned(),
    'banReason': isBanned() ? banReason : null,
    'banExpiresAt': isBanned() ? banExpiresAt?.toIso8601String() : null,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory AuthAdminUserState.fromJson(Map<String, dynamic> json) =>
      AuthAdminUserState(
        userId: _requiredString(json, 'userId'),
        banned: json['banned'] == true,
        banReason: json['banReason']?.toString(),
        banExpiresAt: _optionalDate(json['banExpiresAt']),
        createdAt: _requiredDate(json, 'createdAt'),
        updatedAt: _requiredDate(json, 'updatedAt'),
      );
}

final class AuthAdminUser {
  const AuthAdminUser({required this.user, required this.state});

  final AuthUser user;
  final AuthAdminUserState state;

  Map<String, dynamic> toJson() => {
    ...user.redacted().toJson(),
    ...state.toJson(),
  };

  factory AuthAdminUser.fromJson(Map<String, dynamic> json) => AuthAdminUser(
    user: AuthUser.fromJson(json),
    state: AuthAdminUserState.fromJson(json),
  );
}

enum AuthAdminUserSortField { id, email, name }

final class AuthAdminUserQuery {
  const AuthAdminUserQuery({
    this.search,
    this.id,
    this.email,
    this.name,
    this.role,
    this.banned,
    this.sortBy = AuthAdminUserSortField.id,
    this.descending = false,
    this.limit = 100,
    this.offset = 0,
  });

  final String? search;
  final String? id;
  final String? email;
  final String? name;
  final String? role;
  final bool? banned;
  final AuthAdminUserSortField sortBy;
  final bool descending;
  final int limit;
  final int offset;
}

final class AuthAdminUserPage {
  const AuthAdminUserPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<AuthAdminUser> items;
  final int total;
  final int limit;
  final int offset;

  Map<String, dynamic> toJson() => {
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'total': total,
    'limit': limit,
    'offset': offset,
  };

  factory AuthAdminUserPage.fromJson(Map<String, dynamic> json) =>
      AuthAdminUserPage(
        items: _mapList(json['items']).map(AuthAdminUser.fromJson).toList(),
        total: _integer(json['total']),
        limit: _integer(json['limit']),
        offset: _integer(json['offset']),
      );
}

final class AuthAdminSession {
  const AuthAdminSession({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.expiresAt,
    required this.lastUsedAt,
    required this.authenticationMethod,
    required this.active,
    this.revokedAt,
    this.ipAddress,
    this.userAgent,
    this.impersonatedBy,
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
  final bool active;
  final String? impersonatedBy;

  factory AuthAdminSession.fromRecord(AuthSessionRecord record) =>
      AuthAdminSession(
        id: record.id,
        userId: record.userId,
        createdAt: record.createdAt.toUtc(),
        expiresAt: record.expiresAt.toUtc(),
        lastUsedAt: record.lastUsedAt.toUtc(),
        revokedAt: record.revokedAt?.toUtc(),
        ipAddress: record.ipAddress,
        userAgent: record.userAgent,
        authenticationMethod: record.authenticationMethod,
        active: record.isActive(),
        impersonatedBy: record.impersonatedBy,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'lastUsedAt': lastUsedAt.toIso8601String(),
    'revokedAt': revokedAt?.toIso8601String(),
    'ipAddress': ipAddress,
    'userAgent': userAgent,
    'authenticationMethod': authenticationMethod,
    'active': active,
    'impersonatedBy': impersonatedBy,
  };

  factory AuthAdminSession.fromJson(Map<String, dynamic> json) =>
      AuthAdminSession(
        id: _requiredString(json, 'id'),
        userId: _requiredString(json, 'userId'),
        createdAt: _requiredDate(json, 'createdAt'),
        expiresAt: _requiredDate(json, 'expiresAt'),
        lastUsedAt: _requiredDate(json, 'lastUsedAt'),
        revokedAt: _optionalDate(json['revokedAt']),
        ipAddress: json['ipAddress']?.toString(),
        userAgent: json['userAgent']?.toString(),
        authenticationMethod: _requiredString(json, 'authenticationMethod'),
        active: json['active'] == true,
        impersonatedBy: json['impersonatedBy']?.toString(),
      );
}

final class AuthAdminWarning {
  const AuthAdminWarning({required this.code, this.message});
  final String code;
  final String? message;
  Map<String, dynamic> toJson() => {'code': code, 'message': message};

  factory AuthAdminWarning.fromJson(Map<String, dynamic> json) =>
      AuthAdminWarning(
        code: _requiredString(json, 'code'),
        message: json['message']?.toString(),
      );
}

final class AuthAdminMutationResult<T> {
  const AuthAdminMutationResult({
    required this.data,
    this.warnings = const <AuthAdminWarning>[],
  });
  final T data;
  final List<AuthAdminWarning> warnings;
  Map<String, dynamic> toJson(Object? Function(T value) encode) => {
    'data': encode(data),
    'warnings': warnings.map((warning) => warning.toJson()).toList(),
  };
}

final class AuthAdminPermissionResult {
  const AuthAdminPermissionResult({required this.allowed});
  final bool allowed;
  Map<String, dynamic> toJson() => {'allowed': allowed};
}

final class AuthAdminStopImpersonatingResult {
  const AuthAdminStopImpersonatingResult({
    required this.signedOut,
    this.session,
  });

  final bool signedOut;
  final AuthSession? session;

  Map<String, dynamic> toJson() => {
    'signedOut': signedOut,
    'session': session?.toJson(),
  };
}

final class AuthAdminCreateUserDraft {
  AuthAdminCreateUserDraft({
    required this.id,
    required String email,
    required this.name,
    this.image,
    Iterable<String> roles = const ['user'],
    Map<String, dynamic>? attributes,
  }) : email = normalizeAuthEmail(email),
       roles = normalizeAuthAdminRoles(roles),
       attributes = sanitizeAuthAdminAttributes(attributes);

  final String id;
  final String email;
  final String name;
  final String? image;
  final List<String> roles;
  final Map<String, dynamic> attributes;

  AuthUser toUser() => AuthUser(
    id: id,
    email: email,
    name: name,
    image: image,
    roles: roles,
    attributes: attributes,
  );
}

final class AuthAdminUpdateUserDraft {
  AuthAdminUpdateUserDraft({
    required this.user,
    this.name,
    this.image,
    this.clearImage = false,
    Map<String, dynamic>? attributes,
  }) : attributes = attributes == null
           ? null
           : sanitizeAuthAdminAttributes(attributes);
  final AuthUser user;
  final String? name;
  final String? image;
  final bool clearImage;
  final Map<String, dynamic>? attributes;
}

final class AuthAdminHookContext<TContext, T> {
  const AuthAdminHookContext({
    required this.context,
    required this.action,
    required this.actor,
    required this.data,
    this.targetUserId,
  });
  final TContext context;
  final String action;
  final AuthUser actor;
  final T data;
  final String? targetUserId;
}

typedef AuthAdminBeforeHook<TContext, T> =
    FutureOr<T> Function(AuthAdminHookContext<TContext, T> event);
typedef AuthAdminAfterHook<TContext, T> =
    FutureOr<void> Function(AuthAdminHookContext<TContext, T> event);

final class AuthAdminHooks<TContext> {
  const AuthAdminHooks({
    this.beforeUser,
    this.afterUser,
    this.beforeRole,
    this.afterRole,
    this.beforeBan,
    this.afterBan,
    this.afterSession,
    this.beforeDelete,
    this.afterDelete,
    this.beforeImpersonation,
    this.afterImpersonation,
  });

  final AuthAdminBeforeHook<TContext, Object>? beforeUser;
  final AuthAdminAfterHook<TContext, Object>? afterUser;
  final AuthAdminBeforeHook<TContext, Object>? beforeRole;
  final AuthAdminAfterHook<TContext, Object>? afterRole;
  final AuthAdminBeforeHook<TContext, Object>? beforeBan;
  final AuthAdminAfterHook<TContext, Object>? afterBan;
  final AuthAdminAfterHook<TContext, Object>? afterSession;
  final AuthAdminBeforeHook<TContext, Object>? beforeDelete;
  final AuthAdminAfterHook<TContext, Object>? afterDelete;
  final AuthAdminBeforeHook<TContext, Object>? beforeImpersonation;
  final AuthAdminAfterHook<TContext, Object>? afterImpersonation;
}

final class AuthAdminLifecycleEvent {
  AuthAdminLifecycleEvent({
    required this.type,
    required this.actorId,
    required this.targetUserId,
    required this.occurredAt,
    Map<String, dynamic>? data,
  }) : data = sanitizeAuthAdminAttributes(data);
  final String type;
  final String actorId;
  final String targetUserId;
  final DateTime occurredAt;
  final Map<String, dynamic> data;
  Map<String, dynamic> toJson() => {
    'type': type,
    'actorId': actorId,
    'targetUserId': targetUserId,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'data': data,
  };
}

final class AuthAdminInternalFailure {
  const AuthAdminInternalFailure({
    required this.operation,
    required this.error,
    required this.stackTrace,
    required this.targetUserId,
  });
  final String operation;
  final Object error;
  final StackTrace stackTrace;
  final String targetUserId;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('Invalid admin field: $key');
  return value;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = _optionalDate(json[key]);
  if (value == null) throw FormatException('Invalid admin date: $key');
  return value;
}

DateTime? _optionalDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toUtc();

int _integer(Object? value) => value is int ? value : int.parse('$value');

List<Map<String, dynamic>> _mapList(Object? value) => value is List
    ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : const <Map<String, dynamic>>[];
