import 'dart:async';

import 'models.dart';
import 'users.dart' show normalizeAuthEmail;

/// Resource/action permissions assigned to one administrative role.
typedef AuthAdminPermissionSet = Map<String, Iterable<String>>;

/// One permission that must still be held when an admin mutation commits.
final class AuthAdminPermissionRequirement {
  /// Creates an instance of AuthAdminPermissionRequirement.
  const AuthAdminPermissionRequirement(this.resource, this.action);

  /// The resource associated with this value.
  final String resource;

  /// The action associated with this value.
  final String action;
}

/// Immutable authorization policy carried into a backend-owned admin command.
///
/// The backend reloads [actorId] after entering its transaction and evaluates
/// every [requirements] entry against that authoritative user. Explicit
/// administrator IDs receive the built-in `admin` role. Role-based
/// administrators retain only the permissions assigned to their actual roles.
final class AuthAdminMutationAuthorization {
  /// Creates an instance of AuthAdminMutationAuthorization.
  AuthAdminMutationAuthorization({
    required String actorId,
    required Iterable<String> administratorRoles,
    required Iterable<String> administratorUserIds,
    required Map<String, AuthAdminPermissionSet> rolePermissions,
    required Iterable<AuthAdminPermissionRequirement> requirements,
  }) : actorId = actorId.trim(),
       administratorRoles = Set<String>.unmodifiable(
         normalizeAuthAdminRoles(administratorRoles),
       ),
       administratorUserIds = Set<String>.unmodifiable(
         administratorUserIds
             .map((value) => value.trim())
             .where((value) => value.isNotEmpty),
       ),
       rolePermissions = Map<String, Map<String, List<String>>>.unmodifiable({
         for (final entry in rolePermissions.entries)
           entry.key
               .trim()
               .toLowerCase(): Map<String, List<String>>.unmodifiable({
             for (final permission in entry.value.entries)
               permission.key.trim().toLowerCase(): List<String>.unmodifiable(
                 permission.value
                     .map((value) => value.trim().toLowerCase())
                     .where((value) => value.isNotEmpty)
                     .toSet(),
               ),
           }),
       }),
       requirements = List<AuthAdminPermissionRequirement>.unmodifiable(
         requirements,
       ) {
    if (this.actorId.isEmpty) {
      throw ArgumentError.value(actorId, 'actorId', 'must be non-empty');
    }
    if (this.requirements.isEmpty) {
      throw ArgumentError.value(
        requirements,
        'requirements',
        'must not be empty',
      );
    }
  }

  /// The identifier of actor.
  final String actorId;

  /// The roles assigned to this value.
  final Set<String> administratorRoles;

  /// The administrator user ids associated with this value.
  final Set<String> administratorUserIds;

  /// The roles assigned to this value.
  final Map<String, Map<String, List<String>>> rolePermissions;

  /// The requirements associated with this value.
  final List<AuthAdminPermissionRequirement> requirements;

  /// Checks whether the requested operation is authorized.
  bool allows(
    AuthUser actor, {
    Iterable<AuthAdminPermissionRequirement>? additionalRequirements,
  }) {
    final actorRoles = normalizeAuthAdminRoles(actor.roles);
    final idAdministrator = administratorUserIds.contains(actor.id);
    final roleAdministrator = actorRoles.any(administratorRoles.contains);
    if (!idAdministrator && !roleAdministrator) return false;
    final effectiveRoles = idAdministrator
        ? <String>{...actorRoles, 'admin'}
        : actorRoles;
    return <AuthAdminPermissionRequirement>[
      ...requirements,
      ...?additionalRequirements,
    ].every((requirement) {
      final resource = requirement.resource.trim().toLowerCase();
      final action = requirement.action.trim().toLowerCase();
      return effectiveRoles.any((role) {
        final permissions = rolePermissions[role];
        final actions = permissions?[resource] ?? permissions?['*'];
        return actions?.any((value) => value == action || value == '*') == true;
      });
    });
  }
}

/// Normalizes auth admin roles.
List<String> normalizeAuthAdminRoles(Iterable<String> roles) =>
    List<String>.unmodifiable(
      roles
          .map((role) => role.trim().toLowerCase())
          .where((role) => role.isNotEmpty)
          .toSet()
          .toList()
        ..sort(),
    );

/// Sanitizes auth admin attributes.
Map<String, dynamic> sanitizeAuthAdminAttributes(Map<String, dynamic>? value) =>
    sanitizeAuthPublicAttributes(value ?? const <String, dynamic>{});

/// State information for auth admin user state.
final class AuthAdminUserState {
  /// Creates an instance of AuthAdminUserState.
  AuthAdminUserState({
    required this.userId,
    this.banned = false,
    this.banReason,
    DateTime? banExpiresAt,
    this.emailVerified = false,
    this.disabled = false,
    this.disabledReason,
    DateTime? disabledAt,
    DateTime? lockedUntil,
    this.failedLoginAttempts = 0,
    DateTime? lastLoginAt,
    DateTime? lastFailedLoginAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : banExpiresAt = banExpiresAt?.toUtc(),
       disabledAt = disabledAt?.toUtc(),
       lockedUntil = lockedUntil?.toUtc(),
       lastLoginAt = lastLoginAt?.toUtc(),
       lastFailedLoginAt = lastFailedLoginAt?.toUtc(),
       createdAt = (createdAt ?? DateTime.now()).toUtc(),
       updatedAt = (updatedAt ?? DateTime.now()).toUtc();

  /// The identifier of the user.
  final String userId;

  /// The banned associated with this value.
  final bool banned;

  /// The reason associated with this value.
  final String? banReason;

  /// The time at which ban expires occurred.
  final DateTime? banExpiresAt;

  /// The email verified associated with this value.
  final bool emailVerified;

  /// The disabled associated with this value.
  final bool disabled;

  /// The reason associated with this value.
  final String? disabledReason;

  /// The time at which disabled occurred.
  final DateTime? disabledAt;

  /// The time until which locked remains in effect.
  final DateTime? lockedUntil;

  /// The failed login attempts associated with this value.
  final int failedLoginAttempts;

  /// The time of the last login.
  final DateTime? lastLoginAt;

  /// The time of the last failed login.
  final DateTime? lastFailedLoginAt;

  /// The time at which created occurred.
  final DateTime createdAt;

  /// The time at which updated occurred.
  final DateTime updatedAt;

  /// Returns whether this value is banned.
  bool isBanned({DateTime? now}) =>
      banned &&
      (banExpiresAt == null ||
          (now ?? DateTime.now()).toUtc().isBefore(banExpiresAt!));

  /// Returns whether this value is locked.
  bool isLocked({DateTime? now}) {
    if (lockedUntil == null) return false;
    return (now ?? DateTime.now()).toUtc().isBefore(lockedUntil!);
  }

  /// Returns whether this value can authenticate.
  bool canAuthenticate({DateTime? now}) {
    if (disabled) return false;
    if (isBanned(now: now)) return false;
    if (isLocked(now: now)) return false;
    return true;
  }

  /// Creates a copy with selected fields replaced.
  AuthAdminUserState copyWith({
    bool? banned,
    String? banReason,
    DateTime? banExpiresAt,
    bool clearBanReason = false,
    bool clearBanExpiresAt = false,
    bool? emailVerified,
    bool? disabled,
    String? disabledReason,
    DateTime? disabledAt,
    DateTime? lockedUntil,
    int? failedLoginAttempts,
    DateTime? lastLoginAt,
    DateTime? lastFailedLoginAt,
    DateTime? updatedAt,
    bool clearDisabled = false,
    bool clearLockedUntil = false,
    bool clearDisabledReason = false,
  }) => AuthAdminUserState(
    userId: userId,
    banned: banned ?? this.banned,
    banReason: clearBanReason ? null : banReason ?? this.banReason,
    banExpiresAt: clearBanExpiresAt ? null : banExpiresAt ?? this.banExpiresAt,
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
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'userId': userId,
    'banned': isBanned(),
    'banReason': isBanned() ? banReason : null,
    'banExpiresAt': isBanned() ? banExpiresAt?.toIso8601String() : null,
    'emailVerified': emailVerified,
    'disabled': disabled,
    'disabledReason': disabledReason,
    'disabledAt': disabledAt?.toIso8601String(),
    'lockedUntil': lockedUntil?.toIso8601String(),
    'failedLoginAttempts': failedLoginAttempts,
    'lastLoginAt': lastLoginAt?.toIso8601String(),
    'lastFailedLoginAt': lastFailedLoginAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Creates an instance from a JSON map.
  factory AuthAdminUserState.fromJson(Map<String, dynamic> json) =>
      AuthAdminUserState(
        userId: _requiredString(json, 'userId'),
        banned: json['banned'] == true,
        banReason: json['banReason']?.toString(),
        banExpiresAt: _optionalDate(json['banExpiresAt']),
        emailVerified: json['emailVerified'] == true,
        disabled: json['disabled'] == true,
        disabledReason: json['disabledReason']?.toString(),
        disabledAt: _optionalDate(json['disabledAt']),
        lockedUntil: _optionalDate(json['lockedUntil']),
        failedLoginAttempts: json['failedLoginAttempts'] as int? ?? 0,
        lastLoginAt: _optionalDate(json['lastLoginAt']),
        lastFailedLoginAt: _optionalDate(json['lastFailedLoginAt']),
        createdAt: _requiredDate(json, 'createdAt'),
        updatedAt: _requiredDate(json, 'updatedAt'),
      );
}

/// Authentication data for auth admin user.
final class AuthAdminUser {
  /// Creates an instance of AuthAdminUser.
  const AuthAdminUser({required this.user, required this.state});

  /// The user associated with this value.
  final AuthUser user;

  /// The state associated with this value.
  final AuthAdminUserState state;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    ...user.redacted().toJson(),
    ...state.toJson(),
  };

  /// Creates an instance from a JSON map.
  factory AuthAdminUser.fromJson(Map<String, dynamic> json) => AuthAdminUser(
    user: AuthUser.fromJson(json),
    state: AuthAdminUserState.fromJson(json),
  );
}

/// Authentication data for auth admin user sort field.
enum AuthAdminUserSortField {
  /// A value representing id.
  id,

  /// A value representing email.
  email,

  /// A value representing name.
  name,
}

/// Query options for auth admin user query.
final class AuthAdminUserQuery {
  /// Creates an instance of AuthAdminUserQuery.
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

  /// The search associated with this value.
  final String? search;

  /// The unique identifier.
  final String? id;

  /// The email associated with this value.
  final String? email;

  /// The name associated with this value.
  final String? name;

  /// The roles assigned to this value.
  final String? role;

  /// The banned associated with this value.
  final bool? banned;

  /// The sort by associated with this value.
  final AuthAdminUserSortField sortBy;

  /// The descending associated with this value.
  final bool descending;

  /// The limit associated with this value.
  final int limit;

  /// The offset associated with this value.
  final int offset;
}

/// A page of auth admin user page.
final class AuthAdminUserPage {
  /// Creates an instance of AuthAdminUserPage.
  const AuthAdminUserPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  /// The items associated with this value.
  final List<AuthAdminUser> items;

  /// The total associated with this value.
  final int total;

  /// The limit associated with this value.
  final int limit;

  /// The offset associated with this value.
  final int offset;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'items': items.map((item) => item.toJson()).toList(growable: false),
    'total': total,
    'limit': limit,
    'offset': offset,
  };

  /// Creates an instance from a JSON map.
  factory AuthAdminUserPage.fromJson(Map<String, dynamic> json) =>
      AuthAdminUserPage(
        items: _mapList(json['items']).map(AuthAdminUser.fromJson).toList(),
        total: _integer(json['total']),
        limit: _integer(json['limit']),
        offset: _integer(json['offset']),
      );
}

/// Authentication data for auth admin session.
final class AuthAdminSession {
  /// Creates an instance of AuthAdminSession.
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

  /// The unique identifier.
  final String id;

  /// The identifier of the user.
  final String userId;

  /// The time at which created occurred.
  final DateTime createdAt;

  /// The time at which expires occurred.
  final DateTime expiresAt;

  /// The time of the last used.
  final DateTime lastUsedAt;

  /// The time at which revoked occurred.
  final DateTime? revokedAt;

  /// The ip address associated with this value.
  final String? ipAddress;

  /// The user agent associated with this value.
  final String? userAgent;

  /// The authentication method associated with this value.
  final String authenticationMethod;

  /// The active associated with this value.
  final bool active;

  /// The impersonated by associated with this value.
  final String? impersonatedBy;

  /// Creates an instance from a persisted record.
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

  /// Converts this value to a JSON-compatible map.
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

  /// Creates an instance from a JSON map.
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

/// Authentication data for auth admin warning.
final class AuthAdminWarning {
  /// Creates an instance of AuthAdminWarning.
  const AuthAdminWarning({required this.code, this.message});

  /// The code associated with this value.
  final String code;

  /// The message associated with this value.
  final String? message;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {'code': code, 'message': message};

  /// Creates an instance from a JSON map.
  factory AuthAdminWarning.fromJson(Map<String, dynamic> json) =>
      AuthAdminWarning(
        code: _requiredString(json, 'code'),
        message: json['message']?.toString(),
      );
}

/// Result returned by auth admin mutation result.
final class AuthAdminMutationResult<T> {
  /// Creates an instance of AuthAdminMutationResult.
  const AuthAdminMutationResult({
    required this.data,
    this.warnings = const <AuthAdminWarning>[],
  });

  /// The data associated with this value.
  final T data;

  /// Non-fatal warnings produced by this operation.
  final List<AuthAdminWarning> warnings;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson(Object? Function(T value) encode) => {
    'data': encode(data),
    'warnings': warnings.map((warning) => warning.toJson()).toList(),
  };
}

/// Secret-free audit fact persisted with one administrative mutation.
final class AuthAdminAuditRecord {
  /// Creates an instance of AuthAdminAuditRecord.
  AuthAdminAuditRecord({
    required this.id,
    required this.operation,
    required this.initiatorUserId,
    required this.targetUserId,
    required DateTime occurredAt,
  }) : occurredAt = occurredAt.toUtc();

  /// The unique identifier.
  final String id;

  /// The operation associated with this value.
  final String operation;

  /// The identifier of initiator user.
  final String initiatorUserId;

  /// The identifier of target user.
  final String targetUserId;

  /// The time at which occurred occurred.
  final DateTime occurredAt;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'operation': operation,
    'initiatorUserId': initiatorUserId,
    'targetUserId': targetUserId,
    'occurredAt': occurredAt.toIso8601String(),
  };
}

/// Result returned by auth admin permission result.
final class AuthAdminPermissionResult {
  /// Creates an instance of AuthAdminPermissionResult.
  const AuthAdminPermissionResult({required this.allowed});

  /// The allowed associated with this value.
  final bool allowed;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {'allowed': allowed};
}

/// Result returned by auth admin stop impersonating result.
final class AuthAdminStopImpersonatingResult {
  /// Creates an instance of AuthAdminStopImpersonatingResult.
  const AuthAdminStopImpersonatingResult({
    required this.signedOut,
    this.session,
  });

  /// The signed out associated with this value.
  final bool signedOut;

  /// The session associated with this value.
  final AuthSession? session;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'signedOut': signedOut,
    'session': session?.toJson(),
  };
}

/// Input draft for auth admin create user draft.
final class AuthAdminCreateUserDraft {
  /// Creates an instance of AuthAdminCreateUserDraft.
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

  /// The unique identifier.
  final String id;

  /// The email associated with this value.
  final String email;

  /// The name associated with this value.
  final String name;

  /// The image associated with this value.
  final String? image;

  /// The roles assigned to this value.
  final List<String> roles;

  /// Additional attributes associated with this value.
  final Map<String, dynamic> attributes;

  /// Performs the to user operation.
  AuthUser toUser() => AuthUser(
    id: id,
    email: email,
    name: name,
    image: image,
    roles: roles,
    attributes: attributes,
  );
}

/// Input draft for auth admin update user draft.
final class AuthAdminUpdateUserDraft {
  /// Creates an instance of AuthAdminUpdateUserDraft.
  AuthAdminUpdateUserDraft({
    required this.user,
    this.name,
    this.image,
    this.clearImage = false,
    Map<String, dynamic>? attributes,
  }) : attributes = attributes == null
           ? null
           : sanitizeAuthAdminAttributes(attributes);

  /// The user associated with this value.
  final AuthUser user;

  /// The name associated with this value.
  final String? name;

  /// The image associated with this value.
  final String? image;

  /// The clear image associated with this value.
  final bool clearImage;

  /// Additional attributes associated with this value.
  final Map<String, dynamic>? attributes;
}

/// Context supplied to auth admin hook context.
final class AuthAdminHookContext<TContext, T> {
  /// Creates an instance of AuthAdminHookContext.
  const AuthAdminHookContext({
    required this.context,
    required this.action,
    required this.actor,
    required this.data,
    this.targetUserId,
  });

  /// The host context associated with this operation.
  final TContext context;

  /// The action associated with this value.
  final String action;

  /// The user performing this operation.
  final AuthUser actor;

  /// The data associated with this value.
  final T data;

  /// The identifier of target user.
  final String? targetUserId;
}

/// Callback that handles auth admin before hook.
typedef AuthAdminBeforeHook<TContext, T> =
    FutureOr<T> Function(AuthAdminHookContext<TContext, T> event);

/// Callback that handles auth admin after hook.
typedef AuthAdminAfterHook<TContext, T> =
    FutureOr<void> Function(AuthAdminHookContext<TContext, T> event);

/// Authentication data for auth admin hooks.
final class AuthAdminHooks<TContext> {
  /// Creates an instance of AuthAdminHooks.
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

  /// The before user associated with this value.
  final AuthAdminBeforeHook<TContext, Object>? beforeUser;

  /// The after user associated with this value.
  final AuthAdminAfterHook<TContext, Object>? afterUser;

  /// The roles assigned to this value.
  final AuthAdminBeforeHook<TContext, Object>? beforeRole;

  /// The roles assigned to this value.
  final AuthAdminAfterHook<TContext, Object>? afterRole;

  /// The before ban associated with this value.
  final AuthAdminBeforeHook<TContext, Object>? beforeBan;

  /// The after ban associated with this value.
  final AuthAdminAfterHook<TContext, Object>? afterBan;

  /// The after session associated with this value.
  final AuthAdminAfterHook<TContext, Object>? afterSession;

  /// The before delete associated with this value.
  final AuthAdminBeforeHook<TContext, Object>? beforeDelete;

  /// The after delete associated with this value.
  final AuthAdminAfterHook<TContext, Object>? afterDelete;

  /// The before impersonation associated with this value.
  final AuthAdminBeforeHook<TContext, Object>? beforeImpersonation;

  /// The after impersonation associated with this value.
  final AuthAdminAfterHook<TContext, Object>? afterImpersonation;
}

/// Lifecycle event for auth admin lifecycle event.
final class AuthAdminLifecycleEvent {
  /// Creates an instance of AuthAdminLifecycleEvent.
  AuthAdminLifecycleEvent({
    required this.type,
    required this.actorId,
    required this.targetUserId,
    required this.occurredAt,
    Map<String, dynamic>? data,
  }) : data = sanitizeAuthAdminAttributes(data);

  /// The type associated with this value.
  final String type;

  /// The identifier of actor.
  final String actorId;

  /// The identifier of target user.
  final String targetUserId;

  /// The time at which occurred occurred.
  final DateTime occurredAt;

  /// The data associated with this value.
  final Map<String, dynamic> data;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'type': type,
    'actorId': actorId,
    'targetUserId': targetUserId,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'data': data,
  };
}

/// Failure details for auth admin internal failure.
final class AuthAdminInternalFailure {
  /// Creates an instance of AuthAdminInternalFailure.
  const AuthAdminInternalFailure({
    required this.operation,
    required this.error,
    required this.stackTrace,
    required this.targetUserId,
  });

  /// The operation associated with this value.
  final String operation;

  /// The error associated with this value.
  final Object error;

  /// The stack trace captured for the failure.
  final StackTrace stackTrace;

  /// The identifier of target user.
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
