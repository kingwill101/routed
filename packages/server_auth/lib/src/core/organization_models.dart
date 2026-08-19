import 'models.dart' show sanitizeAuthPublicAttributes;
import 'users.dart' show normalizeAuthEmail;

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

final class AuthOrganization {
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

  final String id;
  final String name;
  final String slug;
  final String? logo;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
    'logo': logo,
    'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

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

final class AuthOrganizationMember {
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

  final String id;
  final String organizationId;
  final String userId;
  final List<String> roles;
  final Map<String, dynamic> attributes;
  final DateTime createdAt;

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

  Map<String, dynamic> toJson() => {
    'id': id,
    'organizationId': organizationId,
    'userId': userId,
    'roles': roles,
    'attributes': attributes,
    'createdAt': createdAt.toIso8601String(),
  };

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

enum AuthOrganizationInvitationStatus {
  pending,
  accepted,
  rejected,
  canceled,
  expired,
}

final class AuthOrganizationInvitation {
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

  final String id;
  final String organizationId;
  final String email;
  final List<String> roles;
  final String inviterId;
  final AuthOrganizationInvitationStatus status;
  final DateTime expiresAt;
  final DateTime createdAt;
  final String? teamId;
  final Map<String, dynamic> attributes;

  bool isPending([DateTime? now]) =>
      status == AuthOrganizationInvitationStatus.pending &&
      expiresAt.isAfter((now ?? DateTime.now()).toUtc());

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

final class AuthOrganizationPermission {
  AuthOrganizationPermission({
    required String resource,
    required Iterable<String> actions,
  }) : resource = resource.trim().toLowerCase(),
       actions = normalizeAuthOrganizationRoles(actions);

  final String resource;
  final List<String> actions;

  Map<String, dynamic> toJson() => {'resource': resource, 'actions': actions};
}

Map<String, List<String>> normalizeAuthOrganizationPermissions(
  Map<String, Iterable<String>> permissions,
) => Map<String, List<String>>.unmodifiable({
  for (final entry in permissions.entries)
    entry.key.trim().toLowerCase(): normalizeAuthOrganizationRoles(entry.value),
});

final class AuthOrganizationRole {
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

  final String id;
  final String organizationId;
  final String name;
  final Map<String, List<String>> permissions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool predefined;

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

  Map<String, dynamic> toJson() => {
    'id': id,
    'organizationId': organizationId,
    'name': name,
    'permissions': permissions,
    'predefined': predefined,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

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

final class AuthOrganizationTeam {
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

  final String id;
  final String organizationId;
  final String name;
  final Map<String, dynamic> attributes;
  final DateTime createdAt;
  final DateTime updatedAt;

  AuthOrganizationTeam copyWith({String? name, DateTime? updatedAt}) =>
      AuthOrganizationTeam(
        id: id,
        organizationId: organizationId,
        name: name ?? this.name,
        attributes: attributes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'organizationId': organizationId,
    'name': name,
    'attributes': attributes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

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

final class AuthOrganizationTeamMember {
  AuthOrganizationTeamMember({
    required this.id,
    required this.teamId,
    required this.userId,
    required DateTime createdAt,
  }) : createdAt = _utc(createdAt);

  final String id;
  final String teamId;
  final String userId;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'teamId': teamId,
    'userId': userId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory AuthOrganizationTeamMember.fromJson(Map<String, dynamic> json) =>
      AuthOrganizationTeamMember(
        id: _requiredString(json, 'id'),
        teamId: _requiredString(json, 'teamId'),
        userId: _requiredString(json, 'userId'),
        createdAt: _requiredDate(json, 'createdAt'),
      );
}

final class AuthOrganizationPage<T> {
  const AuthOrganizationPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<T> items;
  final int total;
  final int limit;
  final int offset;

  Map<String, dynamic> toJson(Object? Function(T value) encode) => {
    'items': items.map(encode).toList(growable: false),
    'total': total,
    'limit': limit,
    'offset': offset,
  };
}

final class AuthOrganizationDetails {
  const AuthOrganizationDetails({
    required this.organization,
    required this.members,
    required this.invitations,
    required this.teams,
  });

  final AuthOrganization organization;
  final AuthOrganizationPage<AuthOrganizationMember> members;
  final List<AuthOrganizationInvitation> invitations;
  final List<AuthOrganizationTeam> teams;

  Map<String, dynamic> toJson() => {
    'organization': organization.toJson(),
    'members': members.toJson((member) => member.toJson()),
    'invitations': invitations.map((value) => value.toJson()).toList(),
    'teams': teams.map((value) => value.toJson()).toList(),
  };
}

final class AuthOrganizationWarning {
  const AuthOrganizationWarning({required this.code, this.message});

  final String code;
  final String? message;

  Map<String, dynamic> toJson() => {'code': code, 'message': message};
}

final class AuthOrganizationMutationResult<T> {
  const AuthOrganizationMutationResult({
    required this.data,
    this.warnings = const <AuthOrganizationWarning>[],
  });

  final T data;
  final List<AuthOrganizationWarning> warnings;

  Map<String, dynamic> toJson(Object? Function(T value) encode) => {
    'data': encode(data),
    'warnings': warnings.map((warning) => warning.toJson()).toList(),
  };
}

final class AuthOrganizationPermissionResult {
  const AuthOrganizationPermissionResult({
    required this.allowed,
    required this.organizationId,
  });

  final bool allowed;
  final String organizationId;

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
