import 'models.dart' show sanitizeAuthPublicAttributes;
import 'users.dart' show normalizeAuthEmail;

/// Normalizes auth organization roles.
List<String> normalizeAuthOrganizationRoles(Iterable<String> roles) {
  final normalized =
      roles
          .map((role) => role.trim().toLowerCase())
          .where((role) => role.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
  return List<String>.unmodifiable(normalized);
}

Map<String, dynamic> _attributes(Map<String, dynamic>? value) =>
    Map<String, dynamic>.unmodifiable(
      sanitizeAuthPublicAttributes(value ?? const <String, dynamic>{}),
    );

DateTime _utc(DateTime value) => value.toUtc();

/// Authentication data for auth organization.
final class AuthOrganization {
  /// Creates an instance of AuthOrganization.
  AuthOrganization({
    required this.id,
    required this.name,
    required this.slug,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.logo,
    Map<String, dynamic>? metadata,
  }) : metadata = _attributes(metadata),
       createdAt = _utc(createdAt),
       updatedAt = _utc(updatedAt);

  /// The unique identifier.
  final String id;

  /// The name associated with this value.
  final String name;

  /// The slug associated with this value.
  final String slug;

  /// The logo associated with this value.
  final String? logo;

  /// The metadata associated with this value.
  final Map<String, dynamic> metadata;

  /// The time at which created occurred.
  final DateTime createdAt;

  /// The time at which updated occurred.
  final DateTime updatedAt;

  /// Creates a copy with selected fields replaced.
  AuthOrganization copyWith({
    String? name,
    String? slug,
    Object? logo = _unset,
    Object? metadata = _unset,
    DateTime? updatedAt,
  }) => AuthOrganization(
    id: id,
    name: name ?? this.name,
    slug: slug ?? this.slug,
    logo: identical(logo, _unset) ? this.logo : logo as String?,
    metadata: identical(metadata, _unset)
        ? this.metadata
        : metadata as Map<String, dynamic>?,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
    'logo': logo,
    'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Creates an instance from a JSON map.
  factory AuthOrganization.fromJson(Map<String, dynamic> json) =>
      AuthOrganization(
        id: _requiredString(json, 'id'),
        name: _requiredString(json, 'name'),
        slug: _requiredString(json, 'slug'),
        logo: json['logo']?.toString(),
        metadata: _map(json['metadata']),
        createdAt: _requiredDate(json, 'createdAt'),
        updatedAt: _requiredDate(json, 'updatedAt'),
      );
}

/// Authentication data for auth organization member.
final class AuthOrganizationMember {
  /// Creates an instance of AuthOrganizationMember.
  AuthOrganizationMember({
    required this.id,
    required this.organizationId,
    required this.userId,
    required Iterable<String> roles,
    required DateTime createdAt,
    Map<String, dynamic>? attributes,
  }) : roles = normalizeAuthOrganizationRoles(roles),
       attributes = _attributes(attributes),
       createdAt = _utc(createdAt);

  /// The unique identifier.
  final String id;

  /// The identifier of the organization.
  final String organizationId;

  /// The identifier of the user.
  final String userId;

  /// The roles assigned to this value.
  final List<String> roles;

  /// Additional attributes associated with this value.
  final Map<String, dynamic> attributes;

  /// The time at which created occurred.
  final DateTime createdAt;

  /// Creates a copy with selected fields replaced.
  AuthOrganizationMember copyWith({
    Iterable<String>? roles,
    Map<String, dynamic>? attributes,
  }) => AuthOrganizationMember(
    id: id,
    organizationId: organizationId,
    userId: userId,
    roles: roles ?? this.roles,
    attributes: attributes ?? this.attributes,
    createdAt: createdAt,
  );

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'organizationId': organizationId,
    'userId': userId,
    'roles': roles,
    'attributes': attributes,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Creates an instance from a JSON map.
  factory AuthOrganizationMember.fromJson(Map<String, dynamic> json) =>
      AuthOrganizationMember(
        id: _requiredString(json, 'id'),
        organizationId: _requiredString(json, 'organizationId'),
        userId: _requiredString(json, 'userId'),
        roles: _strings(json['roles']),
        attributes: _map(json['attributes']),
        createdAt: _requiredDate(json, 'createdAt'),
      );
}

/// Authentication data for auth organization invitation status.
enum AuthOrganizationInvitationStatus {
  /// A value representing pending.
  pending,

  /// A value representing accepted.
  accepted,

  /// A value representing rejected.
  rejected,

  /// A value representing canceled.
  canceled,

  /// A value representing expired.
  expired,
}

/// Authentication data for auth organization invitation.
final class AuthOrganizationInvitation {
  /// Creates an instance of AuthOrganizationInvitation.
  AuthOrganizationInvitation({
    required this.id,
    required this.organizationId,
    required String email,
    required Iterable<String> roles,
    required this.inviterId,
    required this.status,
    required DateTime expiresAt,
    required DateTime createdAt,
    this.teamId,
    Map<String, dynamic>? attributes,
  }) : email = normalizeAuthEmail(email),
       roles = normalizeAuthOrganizationRoles(roles),
       attributes = _attributes(attributes),
       expiresAt = _utc(expiresAt),
       createdAt = _utc(createdAt);

  /// The unique identifier.
  final String id;

  /// The identifier of the organization.
  final String organizationId;

  /// The email associated with this value.
  final String email;

  /// The roles assigned to this value.
  final List<String> roles;

  /// The identifier of inviter.
  final String inviterId;

  /// The status associated with this value.
  final AuthOrganizationInvitationStatus status;

  /// The time at which expires occurred.
  final DateTime expiresAt;

  /// The time at which created occurred.
  final DateTime createdAt;

  /// The identifier of the team.
  final String? teamId;

  /// Additional attributes associated with this value.
  final Map<String, dynamic> attributes;

  /// Returns whether this value is pending.
  bool isPending([DateTime? now]) =>
      status == AuthOrganizationInvitationStatus.pending &&
      expiresAt.isAfter((now ?? DateTime.now()).toUtc());

  /// Creates a copy with selected fields replaced.
  AuthOrganizationInvitation copyWith({
    Iterable<String>? roles,
    AuthOrganizationInvitationStatus? status,
    DateTime? expiresAt,
    String? teamId,
  }) => AuthOrganizationInvitation(
    id: id,
    organizationId: organizationId,
    email: email,
    roles: roles ?? this.roles,
    inviterId: inviterId,
    status: status ?? this.status,
    expiresAt: expiresAt ?? this.expiresAt,
    createdAt: createdAt,
    teamId: teamId ?? this.teamId,
    attributes: attributes,
  );

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson({bool includeActionId = true}) => {
    if (includeActionId) 'id': id,
    'organizationId': organizationId,
    'email': email,
    'roles': roles,
    'inviterId': inviterId,
    'status': status.name,
    'expiresAt': expiresAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'teamId': teamId,
    'attributes': attributes,
  };

  /// Creates an instance from a JSON map.
  factory AuthOrganizationInvitation.fromJson(Map<String, dynamic> json) =>
      AuthOrganizationInvitation(
        id: _requiredString(json, 'id'),
        organizationId: _requiredString(json, 'organizationId'),
        email: _requiredString(json, 'email'),
        roles: _strings(json['roles']),
        inviterId: _requiredString(json, 'inviterId'),
        status: AuthOrganizationInvitationStatus.values.firstWhere(
          (value) => value.name == json['status'],
        ),
        expiresAt: _requiredDate(json, 'expiresAt'),
        createdAt: _requiredDate(json, 'createdAt'),
        teamId: json['teamId']?.toString(),
        attributes: _map(json['attributes']),
      );
}

/// Permission data for auth organization permission.
final class AuthOrganizationPermission {
  /// Creates an instance of AuthOrganizationPermission.
  AuthOrganizationPermission({
    required String resource,
    required Iterable<String> actions,
  }) : resource = resource.trim().toLowerCase(),
       actions = normalizeAuthOrganizationRoles(actions);

  /// The resource associated with this value.
  final String resource;

  /// The actions associated with this value.
  final List<String> actions;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {'resource': resource, 'actions': actions};
}

/// Normalizes auth organization permissions.
Map<String, List<String>> normalizeAuthOrganizationPermissions(
  Map<String, Iterable<String>> permissions,
) => Map<String, List<String>>.unmodifiable({
  for (final entry in permissions.entries)
    entry.key.trim().toLowerCase(): normalizeAuthOrganizationRoles(entry.value),
});

/// Authentication data for auth organization role.
final class AuthOrganizationRole {
  /// Creates an instance of AuthOrganizationRole.
  AuthOrganizationRole({
    required this.id,
    required this.organizationId,
    required String name,
    required Map<String, Iterable<String>> permissions,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.predefined = false,
  }) : name = name.trim().toLowerCase(),
       permissions = normalizeAuthOrganizationPermissions(permissions),
       createdAt = _utc(createdAt),
       updatedAt = _utc(updatedAt);

  /// The unique identifier.
  final String id;

  /// The identifier of the organization.
  final String organizationId;

  /// The name associated with this value.
  final String name;

  /// The permissions assigned to this value.
  final Map<String, List<String>> permissions;

  /// The time at which created occurred.
  final DateTime createdAt;

  /// The time at which updated occurred.
  final DateTime updatedAt;

  /// The predefined associated with this value.
  final bool predefined;

  /// Creates a copy with selected fields replaced.
  AuthOrganizationRole copyWith({
    String? name,
    Map<String, Iterable<String>>? permissions,
    DateTime? updatedAt,
  }) => AuthOrganizationRole(
    id: id,
    organizationId: organizationId,
    name: name ?? this.name,
    permissions: permissions ?? this.permissions,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    predefined: predefined,
  );

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'organizationId': organizationId,
    'name': name,
    'permissions': permissions,
    'predefined': predefined,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Creates an instance from a JSON map.
  factory AuthOrganizationRole.fromJson(Map<String, dynamic> json) =>
      AuthOrganizationRole(
        id: _requiredString(json, 'id'),
        organizationId: _requiredString(json, 'organizationId'),
        name: _requiredString(json, 'name'),
        permissions: _permissionMap(json['permissions']),
        predefined: json['predefined'] == true,
        createdAt: _requiredDate(json, 'createdAt'),
        updatedAt: _requiredDate(json, 'updatedAt'),
      );
}

/// Authentication data for auth organization team.
final class AuthOrganizationTeam {
  /// Creates an instance of AuthOrganizationTeam.
  AuthOrganizationTeam({
    required this.id,
    required this.organizationId,
    required this.name,
    required DateTime createdAt,
    required DateTime updatedAt,
    Map<String, dynamic>? attributes,
  }) : attributes = _attributes(attributes),
       createdAt = _utc(createdAt),
       updatedAt = _utc(updatedAt);

  /// The unique identifier.
  final String id;

  /// The identifier of the organization.
  final String organizationId;

  /// The name associated with this value.
  final String name;

  /// Additional attributes associated with this value.
  final Map<String, dynamic> attributes;

  /// The time at which created occurred.
  final DateTime createdAt;

  /// The time at which updated occurred.
  final DateTime updatedAt;

  /// Creates a copy with selected fields replaced.
  AuthOrganizationTeam copyWith({String? name, DateTime? updatedAt}) =>
      AuthOrganizationTeam(
        id: id,
        organizationId: organizationId,
        name: name ?? this.name,
        attributes: attributes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'organizationId': organizationId,
    'name': name,
    'attributes': attributes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Creates an instance from a JSON map.
  factory AuthOrganizationTeam.fromJson(Map<String, dynamic> json) =>
      AuthOrganizationTeam(
        id: _requiredString(json, 'id'),
        organizationId: _requiredString(json, 'organizationId'),
        name: _requiredString(json, 'name'),
        attributes: _map(json['attributes']),
        createdAt: _requiredDate(json, 'createdAt'),
        updatedAt: _requiredDate(json, 'updatedAt'),
      );
}

/// Authentication data for auth organization team member.
final class AuthOrganizationTeamMember {
  /// Creates an instance of AuthOrganizationTeamMember.
  AuthOrganizationTeamMember({
    required this.id,
    required this.teamId,
    required this.userId,
    required DateTime createdAt,
  }) : createdAt = _utc(createdAt);

  /// The unique identifier.
  final String id;

  /// The identifier of the team.
  final String teamId;

  /// The identifier of the user.
  final String userId;

  /// The time at which created occurred.
  final DateTime createdAt;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'teamId': teamId,
    'userId': userId,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Creates an instance from a JSON map.
  factory AuthOrganizationTeamMember.fromJson(Map<String, dynamic> json) =>
      AuthOrganizationTeamMember(
        id: _requiredString(json, 'id'),
        teamId: _requiredString(json, 'teamId'),
        userId: _requiredString(json, 'userId'),
        createdAt: _requiredDate(json, 'createdAt'),
      );
}

/// A page of auth organization page.
final class AuthOrganizationPage<T> {
  /// Creates an instance of AuthOrganizationPage.
  const AuthOrganizationPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  /// The items associated with this value.
  final List<T> items;

  /// The total associated with this value.
  final int total;

  /// The limit associated with this value.
  final int limit;

  /// The offset associated with this value.
  final int offset;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson(Object? Function(T value) encode) => {
    'items': items.map(encode).toList(growable: false),
    'total': total,
    'limit': limit,
    'offset': offset,
  };
}

/// Authentication data for auth organization details.
final class AuthOrganizationDetails {
  /// Creates an instance of AuthOrganizationDetails.
  const AuthOrganizationDetails({
    required this.organization,
    required this.members,
    required this.invitations,
    required this.teams,
  });

  /// The organization associated with this value.
  final AuthOrganization organization;

  /// The members associated with this value.
  final AuthOrganizationPage<AuthOrganizationMember> members;

  /// The invitations associated with this value.
  final List<AuthOrganizationInvitation> invitations;

  /// The teams associated with this value.
  final List<AuthOrganizationTeam> teams;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'organization': organization.toJson(),
    'members': members.toJson((member) => member.toJson()),
    'invitations': invitations.map((value) => value.toJson()).toList(),
    'teams': teams.map((value) => value.toJson()).toList(),
  };
}

/// Authentication data for auth organization warning.
final class AuthOrganizationWarning {
  /// Creates an instance of AuthOrganizationWarning.
  const AuthOrganizationWarning({required this.code, this.message});

  /// The code associated with this value.
  final String code;

  /// The message associated with this value.
  final String? message;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {'code': code, 'message': message};
}

/// Result returned by auth organization mutation result.
final class AuthOrganizationMutationResult<T> {
  /// Creates an instance of AuthOrganizationMutationResult.
  const AuthOrganizationMutationResult({
    required this.data,
    this.warnings = const <AuthOrganizationWarning>[],
  });

  /// The data associated with this value.
  final T data;

  /// Non-fatal warnings produced by this operation.
  final List<AuthOrganizationWarning> warnings;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson(Object? Function(T value) encode) => {
    'data': encode(data),
    'warnings': warnings.map((warning) => warning.toJson()).toList(),
  };
}

/// Result returned by auth organization permission result.
final class AuthOrganizationPermissionResult {
  /// Creates an instance of AuthOrganizationPermissionResult.
  const AuthOrganizationPermissionResult({
    required this.allowed,
    required this.organizationId,
  });

  /// The allowed associated with this value.
  final bool allowed;

  /// The identifier of the organization.
  final String organizationId;

  /// Converts this value to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'allowed': allowed,
    'organizationId': organizationId,
  };
}

const Object _unset = Object();

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw FormatException('Invalid organization field: $key');
  return value;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = DateTime.tryParse(json[key]?.toString() ?? '');
  if (value == null) throw FormatException('Invalid organization date: $key');
  return value.toUtc();
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? <String, dynamic>{
        for (final entry in value.entries) '${entry.key}': entry.value,
      }
    : const <String, dynamic>{};

Iterable<String> _strings(Object? value) =>
    value is Iterable ? value.map((item) => item.toString()) : const <String>[];

Map<String, Iterable<String>> _permissionMap(Object? value) => value is Map
    ? <String, Iterable<String>>{
        for (final entry in value.entries)
          '${entry.key}': _strings(entry.value),
      }
    : const <String, Iterable<String>>{};
