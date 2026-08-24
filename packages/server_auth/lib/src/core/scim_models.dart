/// SCIM 2.0 core User schema identifier.
const String authScimUserSchema = 'urn:ietf:params:scim:schemas:core:2.0:User';

/// SCIM 2.0 core Group schema identifier.
const String authScimGroupSchema =
    'urn:ietf:params:scim:schemas:core:2.0:Group';

/// SCIM 2.0 service-provider configuration schema identifier.
const String authScimServiceProviderConfigSchema =
    'urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig';

/// SCIM 2.0 resource-type schema identifier.
const String authScimResourceTypeSchema =
    'urn:ietf:params:scim:schemas:core:2.0:ResourceType';

/// SCIM 2.0 schema-resource schema identifier.
const String authScimSchemaSchema =
    'urn:ietf:params:scim:schemas:core:2.0:Schema';

/// SCIM 2.0 list response schema identifier.
const String authScimListResponseSchema =
    'urn:ietf:params:scim:api:messages:2.0:ListResponse';

/// SCIM 2.0 patch request schema identifier.
const String authScimPatchOperationSchema =
    'urn:ietf:params:scim:api:messages:2.0:PatchOp';

/// SCIM 2.0 error response schema identifier.
const String authScimErrorSchema =
    'urn:ietf:params:scim:api:messages:2.0:Error';

/// Operation scope granted to one authenticated SCIM credential.
enum AuthScimScope {
  /// Permits reading users.
  usersRead,

  /// Permits creating and changing users.
  usersWrite,

  /// Permits reading groups.
  groupsRead,

  /// Permits creating and changing groups.
  groupsWrite,
}

/// Immutable connection identity resolved atomically from one bearer token.
///
/// The application-owned resolver must return the connection and all of its
/// isolation boundaries in one result. Routed performs no secondary tenant or
/// connection lookup after authentication.
final class AuthScimConnectionIdentity {
  /// Creates an immutable connection identity from a verified bearer token.
  AuthScimConnectionIdentity({
    required String connectionId,
    required String credentialId,
    required String tenantId,
    required String organizationId,
    required String provisioningDomainId,
    required String subjectId,
    required Iterable<AuthScimScope> scopes,
    this.expiresAt,
  }) : connectionId = _requiredBounded(connectionId, 'connectionId', 256),
       credentialId = _requiredBounded(credentialId, 'credentialId', 256),
       tenantId = _requiredBounded(tenantId, 'tenantId', 256),
       organizationId = _requiredBounded(organizationId, 'organizationId', 256),
       provisioningDomainId = _requiredBounded(
         provisioningDomainId,
         'provisioningDomainId',
         256,
       ),
       subjectId = _requiredBounded(subjectId, 'subjectId', 256),
       scopes = Set<AuthScimScope>.unmodifiable(scopes);

  /// Managed connection identifier.
  final String connectionId;

  /// Credential identifier used for authentication.
  final String credentialId;

  /// Tenant containing the connection.
  final String tenantId;

  /// Organization containing the connection.
  final String organizationId;

  /// Provisioning domain receiving the operation.
  final String provisioningDomainId;

  /// Application subject that owns the connection.
  final String subjectId;

  /// Scopes granted to the credential.
  final Set<AuthScimScope> scopes;

  /// Credential expiry timestamp, when configured.
  final DateTime? expiresAt;

  /// Whether [scope] is granted, including read access implied by write.
  bool allows(AuthScimScope scope) =>
      scopes.contains(scope) ||
      scope == AuthScimScope.usersRead &&
          scopes.contains(AuthScimScope.usersWrite) ||
      scope == AuthScimScope.groupsRead &&
          scopes.contains(AuthScimScope.groupsWrite);

  /// Whether this identity is expired at [instant].
  bool isExpiredAt(DateTime instant) =>
      expiresAt != null && !expiresAt!.toUtc().isAfter(instant.toUtc());

  @override
  String toString() =>
      'AuthScimConnectionIdentity(connectionId: $connectionId, '
      'credentialId: $credentialId, tenantId: $tenantId, '
      'organizationId: $organizationId, '
      'provisioningDomainId: $provisioningDomainId, '
      'subjectId: $subjectId, '
      'scopes: ${scopes.map((value) => value.name).join(',')})';
}

/// Connection-scoped application store context for one SCIM request.
final class AuthScimProvisioningContext {
  /// Creates a request context for [connection].
  const AuthScimProvisioningContext({required this.connection});

  /// Verified connection identity for the request.
  final AuthScimConnectionIdentity connection;

  /// Managed connection identifier.
  String get connectionId => connection.connectionId;

  /// Tenant containing the connection.
  String get tenantId => connection.tenantId;

  /// Organization containing the connection.
  String get organizationId => connection.organizationId;

  /// Provisioning domain receiving the operation.
  String get provisioningDomainId => connection.provisioningDomainId;

  /// Application subject that owns the connection.
  String get subjectId => connection.subjectId;
}

/// Typed SCIM user name.
final class AuthScimUserName {
  /// Creates a bounded SCIM name value.
  AuthScimUserName({
    this.formatted,
    this.familyName,
    this.givenName,
    this.middleName,
    this.honorificPrefix,
    this.honorificSuffix,
  }) {
    for (final value in <String?>[
      formatted,
      familyName,
      givenName,
      middleName,
      honorificPrefix,
      honorificSuffix,
    ]) {
      if (value != null) _bounded(value, 'name', 256);
    }
  }

  /// Decodes a bounded SCIM name object.
  factory AuthScimUserName.fromJson(Map<String, dynamic> json) {
    _onlyKeys(json, const <String>{
      'formatted',
      'familyName',
      'givenName',
      'middleName',
      'honorificPrefix',
      'honorificSuffix',
    });
    return AuthScimUserName(
      formatted: _optionalString(json, 'formatted', 256),
      familyName: _optionalString(json, 'familyName', 256),
      givenName: _optionalString(json, 'givenName', 256),
      middleName: _optionalString(json, 'middleName', 256),
      honorificPrefix: _optionalString(json, 'honorificPrefix', 128),
      honorificSuffix: _optionalString(json, 'honorificSuffix', 128),
    );
  }

  /// Display-formatted name.
  final String? formatted;

  /// Family name.
  final String? familyName;

  /// Given name.
  final String? givenName;

  /// Middle name.
  final String? middleName;

  /// Honorific prefix.
  final String? honorificPrefix;

  /// Honorific suffix.
  final String? honorificSuffix;

  /// Encodes this name object.
  Map<String, Object?> toJson() => <String, Object?>{
    if (formatted != null) 'formatted': formatted,
    if (familyName != null) 'familyName': familyName,
    if (givenName != null) 'givenName': givenName,
    if (middleName != null) 'middleName': middleName,
    if (honorificPrefix != null) 'honorificPrefix': honorificPrefix,
    if (honorificSuffix != null) 'honorificSuffix': honorificSuffix,
  };
}

/// Typed SCIM user email value.
final class AuthScimUserEmail {
  /// Creates a bounded SCIM email value.
  AuthScimUserEmail({
    required String value,
    this.type,
    this.display,
    this.primary = false,
  }) : value = _requiredBounded(value, 'email.value', 320) {
    if (type != null) _bounded(type!, 'email.type', 64);
    if (display != null) _bounded(display!, 'email.display', 256);
  }

  /// Decodes a bounded SCIM email object.
  factory AuthScimUserEmail.fromJson(Map<String, dynamic> json) {
    _onlyKeys(json, const <String>{'value', 'type', 'display', 'primary'});
    final primary = json['primary'];
    if (primary != null && primary is! bool) {
      throw const FormatException('Invalid SCIM email primary value.');
    }
    return AuthScimUserEmail(
      value: _requiredString(json, 'value', 320),
      type: _optionalString(json, 'type', 64),
      display: _optionalString(json, 'display', 256),
      primary: primary == true,
    );
  }

  /// Email address value.
  final String value;

  /// Application-defined email type.
  final String? type;

  /// Presentation label for the email address.
  final String? display;

  /// Whether this is the primary email address.
  final bool primary;

  /// Encodes this email object.
  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    if (type != null) 'type': type,
    if (display != null) 'display': display,
    if (primary) 'primary': true,
  };
}

/// Strict application-owned data accepted for SCIM User provisioning.
final class AuthScimUserData {
  /// Creates strict application-owned data for a SCIM User.
  AuthScimUserData({
    required String userName,
    this.externalId,
    this.active = true,
    this.name,
    this.displayName,
    Iterable<AuthScimUserEmail> emails = const <AuthScimUserEmail>[],
  }) : userName = _requiredBounded(userName, 'userName', 256),
       emails = List<AuthScimUserEmail>.unmodifiable(emails) {
    if (externalId != null) _bounded(externalId!, 'externalId', 256);
    if (displayName != null) _bounded(displayName!, 'displayName', 256);
    _validateEmails(this.emails);
  }

  /// Decodes strict SCIM User mutation data.
  factory AuthScimUserData.fromJson(Map<String, dynamic> json) {
    _onlyKeys(json, const <String>{
      'schemas',
      'externalId',
      'userName',
      'active',
      'name',
      'displayName',
      'emails',
    });
    _requireSchemas(json, authScimUserSchema);
    final active = json['active'];
    if (active != null && active is! bool) {
      throw const FormatException('Invalid SCIM active value.');
    }
    return AuthScimUserData(
      userName: _requiredString(json, 'userName', 256),
      externalId: _optionalString(json, 'externalId', 256),
      active: active is! bool || active,
      name: _optionalObject(json, 'name', AuthScimUserName.fromJson),
      displayName: _optionalString(json, 'displayName', 256),
      emails: _emails(json['emails']),
    );
  }

  /// User name used by the SCIM directory.
  final String userName;

  /// Application-owned external identifier.
  final String? externalId;

  /// Whether the user is active in the directory.
  final bool active;

  /// Structured name, when supplied.
  final AuthScimUserName? name;

  /// Display name, when supplied.
  final String? displayName;

  /// Email values associated with the user.
  final List<AuthScimUserEmail> emails;

  /// Encodes this User data object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemas': const <String>[authScimUserSchema],
    if (externalId != null) 'externalId': externalId,
    'userName': userName,
    'active': active,
    if (name != null) 'name': name!.toJson(),
    if (displayName != null) 'displayName': displayName,
    if (emails.isNotEmpty)
      'emails': emails.map((value) => value.toJson()).toList(growable: false),
  };
}

/// SCIM resource metadata supplied by the application provisioning store.
final class AuthScimResourceMeta {
  /// Creates resource metadata normalized to UTC.
  AuthScimResourceMeta({
    required DateTime created,
    required DateTime lastModified,
    this.resourceType = 'User',
    this.location,
    this.version,
  }) : created = created.toUtc(),
       lastModified = lastModified.toUtc() {
    _requiredBounded(resourceType, 'resourceType', 64);
    if (version != null) _bounded(version!, 'version', 256);
  }

  /// Resource creation timestamp.
  final DateTime created;

  /// Last modification timestamp.
  final DateTime lastModified;

  /// SCIM resource type name.
  final String resourceType;

  /// Resource location, when exposed by the application.
  final Uri? location;

  /// Application version or entity tag, when available.
  final String? version;

  /// Encodes this resource metadata object.
  Map<String, Object?> toJson() => <String, Object?>{
    'resourceType': resourceType,
    'created': created.toIso8601String(),
    'lastModified': lastModified.toIso8601String(),
    if (location != null) 'location': location.toString(),
    if (version != null) 'version': version,
  };
}

/// Explicit internal lifecycle of a connection-owned directory user.
enum AuthScimDirectoryUserState {
  /// The user is active.
  active,

  /// The user is provisioned but inactive.
  inactive,

  /// The user is retained as a deletion tombstone.
  tombstoned,
}

/// Connection-bound SCIM User resource returned by an application store.
final class AuthScimUser {
  /// Creates a connection-bound SCIM User resource.
  AuthScimUser({
    required String connectionId,
    required String tenantId,
    required String organizationId,
    required String provisioningDomainId,
    required String id,
    required this.data,
    required this.meta,
    required this.state,
    this.tombstonedAt,
  }) : connectionId = _requiredBounded(connectionId, 'connectionId', 256),
       tenantId = _requiredBounded(tenantId, 'tenantId', 256),
       organizationId = _requiredBounded(organizationId, 'organizationId', 256),
       provisioningDomainId = _requiredBounded(
         provisioningDomainId,
         'provisioningDomainId',
         256,
       ),
       id = _requiredBounded(id, 'id', 256) {
    if (meta.resourceType != 'User') {
      throw ArgumentError('SCIM User metadata must use resourceType User.');
    }
    if ((state == AuthScimDirectoryUserState.active) != data.active) {
      throw ArgumentError(
        'SCIM directory lifecycle state must match the active attribute.',
      );
    }
    if ((state == AuthScimDirectoryUserState.tombstoned) !=
        (tombstonedAt != null)) {
      throw ArgumentError(
        'Only tombstoned SCIM users may carry a tombstone timestamp.',
      );
    }
  }

  /// Immutable connection that owns this directory resource.
  final String connectionId;

  /// Internal tenancy boundary. It is deliberately omitted from SCIM JSON.
  final String tenantId;

  /// Internal organization boundary. It is deliberately omitted from JSON.
  final String organizationId;

  /// Application boundary receiving explicit provisioning projections.
  final String provisioningDomainId;

  /// SCIM resource identifier.
  final String id;

  /// Provisioned User attributes.
  final AuthScimUserData data;

  /// Resource metadata returned to the client.
  final AuthScimResourceMeta meta;

  /// Internal lifecycle state.
  final AuthScimDirectoryUserState state;

  /// Tombstone timestamp, when [state] is [AuthScimDirectoryUserState.tombstoned].
  final DateTime? tombstonedAt;

  /// Encodes this User resource without internal tenancy fields.
  Map<String, Object?> toJson() => <String, Object?>{
    ...data.toJson(),
    'id': id,
    'meta': meta.toJson(),
  };
}

/// Attribute supported by the bounded first-slice SCIM filter parser.
enum AuthScimUserFilterAttribute {
  /// Matches the SCIM resource identifier.
  id,

  /// Matches `userName`.
  userName,

  /// Matches `externalId`.
  externalId,

  /// Matches `emails.value`.
  email,
}

/// A bounded SCIM equality filter.
final class AuthScimUserFilter {
  /// Creates an equality filter for [attribute] and [value].
  const AuthScimUserFilter({required this.attribute, required this.value});

  /// Parses the bounded SCIM equality filter syntax.
  factory AuthScimUserFilter.parse(String source) {
    if (source.length > 512 || _containsControl(source)) {
      throw const FormatException('Invalid SCIM filter.');
    }
    final match = _expression.firstMatch(source);
    if (match == null) throw const FormatException('Invalid SCIM filter.');
    final rawAttribute = match.group(1)!.toLowerCase();
    final value = match
        .group(2)!
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\');
    _requiredBounded(value, 'filter.value', 256);
    return AuthScimUserFilter(
      attribute: switch (rawAttribute) {
        'id' => AuthScimUserFilterAttribute.id,
        'username' => AuthScimUserFilterAttribute.userName,
        'externalid' => AuthScimUserFilterAttribute.externalId,
        'emails.value' => AuthScimUserFilterAttribute.email,
        _ => throw const FormatException('Invalid SCIM filter.'),
      },
      value: value,
    );
  }

  /// Attribute tested by this filter.
  final AuthScimUserFilterAttribute attribute;

  /// Exact value to compare.
  final String value;

  static final RegExp _expression = RegExp(
    r'^\s*(id|userName|externalId|emails\.value)\s+eq\s+"((?:[^"\\]|\\["\\])*)"\s*$',
    caseSensitive: false,
  );
}

/// Bounded query supplied to `AuthScimProvisioningStore.listUsers`.
final class AuthScimListUsersQuery {
  /// Creates a bounded User listing query.
  const AuthScimListUsersQuery({
    required this.startIndex,
    required this.count,
    this.filter,
  });

  /// Decodes and bounds a SCIM User listing request.
  factory AuthScimListUsersQuery.fromJson(
    Map<String, dynamic> json, {
    required int defaultPageSize,
    required int maximumPageSize,
    required int maximumStartIndex,
  }) {
    final startIndex = _integer(json['startIndex'], fallback: 1);
    final requestedCount = _integer(json['count'], fallback: defaultPageSize);
    if (startIndex < 1 || startIndex > maximumStartIndex) {
      throw const FormatException('Invalid SCIM startIndex.');
    }
    if (requestedCount < 0) {
      throw const FormatException('Invalid SCIM count.');
    }
    final rawFilter = json['filter'];
    if (rawFilter != null && rawFilter is! String) {
      throw const FormatException('Invalid SCIM filter.');
    }
    final filterText = rawFilter as String?;
    return AuthScimListUsersQuery(
      startIndex: startIndex,
      count: requestedCount.clamp(0, maximumPageSize),
      filter: filterText == null || filterText.trim().isEmpty
          ? null
          : AuthScimUserFilter.parse(filterText),
    );
  }

  /// One-based index of the first requested resource.
  final int startIndex;

  /// Number of resources requested.
  final int count;

  /// Optional equality filter.
  final AuthScimUserFilter? filter;
}

/// Tenant-bound page returned by an application provisioning store.
final class AuthScimUserPage {
  /// Creates a page of connection-bound User resources.
  AuthScimUserPage({
    required Iterable<AuthScimUser> resources,
    required this.totalResults,
  }) : resources = List<AuthScimUser>.unmodifiable(resources) {
    if (totalResults < 0) {
      throw ArgumentError.value(totalResults, 'totalResults');
    }
  }

  /// Resources in this page.
  final List<AuthScimUser> resources;

  /// Total matching resources before pagination.
  final int totalResults;
}

/// Kind of SCIM resource referenced directly by a Group member.
enum AuthScimGroupMemberType {
  /// A User resource.
  user,

  /// A Group resource.
  group,
}

/// One direct, stable SCIM resource reference in a Group.
///
/// [value] is always the SCIM resource identifier. The optional display and
/// reference values are presentation metadata and must never be used to infer
/// an authentication user, application role, or access grant.
final class AuthScimGroupMember {
  /// Creates a bounded direct resource reference.
  AuthScimGroupMember({
    required String value,
    required this.type,
    this.display,
    this.reference,
  }) : value = _requiredBounded(value, 'member.value', 256) {
    if (display != null) _bounded(display!, 'member.display', 256);
    if (reference != null && reference!.toString().length > 2048) {
      throw const FormatException('Invalid SCIM member reference.');
    }
  }

  /// Decodes a bounded Group member object.
  factory AuthScimGroupMember.fromJson(Map<String, dynamic> json) {
    _onlyKeys(json, const <String>{'value', 'type', 'display', r'$ref'});
    final rawType = _requiredString(json, 'type', 16).toLowerCase();
    final rawReference = _optionalString(json, r'$ref', 2048);
    return AuthScimGroupMember(
      value: _requiredString(json, 'value', 256),
      type: switch (rawType) {
        'user' => AuthScimGroupMemberType.user,
        'group' => AuthScimGroupMemberType.group,
        _ => throw const FormatException('Invalid SCIM member type.'),
      },
      display: _optionalString(json, 'display', 256),
      reference: rawReference == null ? null : Uri.parse(rawReference),
    );
  }

  /// Referenced SCIM resource identifier.
  final String value;

  /// Referenced resource type.
  final AuthScimGroupMemberType type;

  /// Optional display label.
  final String? display;

  /// Optional resource reference URI.
  final Uri? reference;

  /// Encodes this Group member object.
  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    r'$ref': ?reference?.toString(),
    'display': ?display,
    'type': switch (type) {
      AuthScimGroupMemberType.user => 'User',
      AuthScimGroupMemberType.group => 'Group',
    },
  };
}

/// Strict application-owned data accepted for SCIM Group provisioning.
final class AuthScimGroupData {
  /// Creates strict application-owned data for a SCIM Group.
  AuthScimGroupData({
    required String displayName,
    this.externalId,
    Iterable<AuthScimGroupMember> members = const <AuthScimGroupMember>[],
    int maximumMembers = 1000,
  }) : displayName = _requiredBounded(displayName, 'displayName', 256),
       members = List<AuthScimGroupMember>.unmodifiable(members) {
    if (externalId != null) _bounded(externalId!, 'externalId', 256);
    _validateGroupMembers(this.members, maximumMembers: maximumMembers);
  }

  /// Decodes strict SCIM Group mutation data.
  factory AuthScimGroupData.fromJson(
    Map<String, dynamic> json, {
    int maximumMembers = 1000,
  }) {
    _onlyKeys(json, const <String>{
      'schemas',
      'externalId',
      'displayName',
      'members',
    });
    _requireSchemas(json, authScimGroupSchema);
    return AuthScimGroupData(
      displayName: _requiredString(json, 'displayName', 256),
      externalId: _optionalString(json, 'externalId', 256),
      members: _groupMembers(json['members'], maximumMembers: maximumMembers),
      maximumMembers: maximumMembers,
    );
  }

  /// Required display name.
  final String displayName;

  /// Application-owned external identifier.
  final String? externalId;

  /// Direct members of the group.
  final List<AuthScimGroupMember> members;

  /// Encodes this Group data object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemas': const <String>[authScimGroupSchema],
    if (externalId != null) 'externalId': externalId,
    'displayName': displayName,
    if (members.isNotEmpty)
      'members': members.map((value) => value.toJson()).toList(growable: false),
  };
}

/// Explicit internal lifecycle of a connection-owned directory group.
enum AuthScimDirectoryGroupState {
  /// The group is active.
  active,

  /// The group is retained as a deletion tombstone.
  tombstoned,
}

/// Connection-bound SCIM Group resource returned by an application store.
final class AuthScimGroup {
  /// Creates a connection-bound SCIM Group resource.
  AuthScimGroup({
    required String connectionId,
    required String tenantId,
    required String organizationId,
    required String provisioningDomainId,
    required String id,
    required this.data,
    required this.meta,
    required this.state,
    this.tombstonedAt,
  }) : connectionId = _requiredBounded(connectionId, 'connectionId', 256),
       tenantId = _requiredBounded(tenantId, 'tenantId', 256),
       organizationId = _requiredBounded(organizationId, 'organizationId', 256),
       provisioningDomainId = _requiredBounded(
         provisioningDomainId,
         'provisioningDomainId',
         256,
       ),
       id = _requiredBounded(id, 'id', 256) {
    if (meta.resourceType != 'Group') {
      throw ArgumentError('SCIM Group metadata must use resourceType Group.');
    }
    if ((state == AuthScimDirectoryGroupState.tombstoned) !=
        (tombstonedAt != null)) {
      throw ArgumentError(
        'Only tombstoned SCIM groups may carry a tombstone timestamp.',
      );
    }
  }

  /// Immutable connection that owns this directory resource.
  final String connectionId;

  /// Internal tenant boundary omitted from SCIM JSON.
  final String tenantId;

  /// Internal organization boundary omitted from SCIM JSON.
  final String organizationId;

  /// Application provisioning boundary.
  final String provisioningDomainId;

  /// SCIM resource identifier.
  final String id;

  /// Provisioned Group attributes.
  final AuthScimGroupData data;

  /// Resource metadata returned to the client.
  final AuthScimResourceMeta meta;

  /// Internal lifecycle state.
  final AuthScimDirectoryGroupState state;

  /// Tombstone timestamp, when [state] is tombstoned.
  final DateTime? tombstonedAt;

  /// Encodes this Group resource without internal tenancy fields.
  Map<String, Object?> toJson() => <String, Object?>{
    ...data.toJson(),
    'id': id,
    'meta': meta.toJson(),
  };
}

/// Attribute supported by the bounded Group filter parser.
enum AuthScimGroupFilterAttribute {
  /// Matches the SCIM resource identifier.
  id,

  /// Matches `displayName`.
  displayName,

  /// Matches `externalId`.
  externalId,
}

/// A bounded equality filter for Group listing.
final class AuthScimGroupFilter {
  /// Creates an equality filter for [attribute] and [value].
  const AuthScimGroupFilter({required this.attribute, required this.value});

  /// Parses the bounded SCIM Group equality filter syntax.
  factory AuthScimGroupFilter.parse(String source) {
    if (source.length > 512 || _containsControl(source)) {
      throw const FormatException('Invalid SCIM Group filter.');
    }
    final match = _expression.firstMatch(source);
    if (match == null) {
      throw const FormatException('Invalid SCIM Group filter.');
    }
    final value = match
        .group(2)!
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', r'\');
    _requiredBounded(value, 'filter.value', 256);
    return AuthScimGroupFilter(
      attribute: switch (match.group(1)!.toLowerCase()) {
        'id' => AuthScimGroupFilterAttribute.id,
        'displayname' => AuthScimGroupFilterAttribute.displayName,
        'externalid' => AuthScimGroupFilterAttribute.externalId,
        _ => throw const FormatException('Invalid SCIM Group filter.'),
      },
      value: value,
    );
  }

  /// Attribute tested by this filter.
  final AuthScimGroupFilterAttribute attribute;

  /// Exact value to compare.
  final String value;

  static final RegExp _expression = RegExp(
    r'^\s*(id|displayName|externalId)\s+eq\s+"((?:[^"\\]|\\["\\])*)"\s*$',
    caseSensitive: false,
  );
}

/// Bounded query supplied to `AuthScimProvisioningStore.listGroups`.
final class AuthScimListGroupsQuery {
  /// Creates a bounded Group listing query.
  const AuthScimListGroupsQuery({
    required this.startIndex,
    required this.count,
    this.filter,
  });

  /// Decodes and bounds a SCIM Group listing request.
  factory AuthScimListGroupsQuery.fromJson(
    Map<String, dynamic> json, {
    required int defaultPageSize,
    required int maximumPageSize,
    required int maximumStartIndex,
  }) {
    final startIndex = _integer(json['startIndex'], fallback: 1);
    final requestedCount = _integer(json['count'], fallback: defaultPageSize);
    if (startIndex < 1 || startIndex > maximumStartIndex) {
      throw const FormatException('Invalid SCIM startIndex.');
    }
    if (requestedCount < 0) throw const FormatException('Invalid SCIM count.');
    final rawFilter = json['filter'];
    if (rawFilter != null && rawFilter is! String) {
      throw const FormatException('Invalid SCIM Group filter.');
    }
    final filterText = rawFilter as String?;
    return AuthScimListGroupsQuery(
      startIndex: startIndex,
      count: requestedCount.clamp(0, maximumPageSize),
      filter: filterText == null || filterText.trim().isEmpty
          ? null
          : AuthScimGroupFilter.parse(filterText),
    );
  }

  /// One-based index of the first requested resource.
  final int startIndex;

  /// Number of resources requested.
  final int count;

  /// Optional equality filter.
  final AuthScimGroupFilter? filter;
}

/// A page of SCIM Group resources returned by a connection-bound query.
final class AuthScimGroupPage {
  /// Creates a page of connection-bound Group resources.
  AuthScimGroupPage({
    required Iterable<AuthScimGroup> resources,
    required this.totalResults,
  }) : resources = List<AuthScimGroup>.unmodifiable(resources) {
    if (totalResults < 0) {
      throw ArgumentError.value(totalResults, 'totalResults');
    }
  }

  /// Resources in this page.
  final List<AuthScimGroup> resources;

  /// Total matching resources before pagination.
  final int totalResults;
}

/// Group attributes supported by the typed patch implementation.
enum AuthScimGroupPatchPath {
  /// Group display name.
  displayName,

  /// Application-owned external identifier.
  externalId,

  /// Direct group membership.
  members,
}

/// One validated SCIM Group patch operation.
final class AuthScimGroupPatchOperation {
  /// Decodes and validates one Group patch operation.
  factory AuthScimGroupPatchOperation.fromJson(
    Map<String, dynamic> json, {
    required int maximumMembers,
  }) {
    _onlyKeys(json, const <String>{'op', 'path', 'value'});
    final kind = switch (_requiredString(json, 'op', 16).toLowerCase()) {
      'add' => AuthScimPatchOperationKind.add,
      'replace' => AuthScimPatchOperationKind.replace,
      'remove' => AuthScimPatchOperationKind.remove,
      _ => throw const FormatException('Invalid SCIM patch operation.'),
    };
    final path = switch (_requiredString(json, 'path', 64).toLowerCase()) {
      'displayname' => AuthScimGroupPatchPath.displayName,
      'externalid' => AuthScimGroupPatchPath.externalId,
      'members' => AuthScimGroupPatchPath.members,
      _ => throw const FormatException('Invalid SCIM Group patch path.'),
    };
    final hasValue = json.containsKey('value');
    if (kind == AuthScimPatchOperationKind.remove) {
      if (path == AuthScimGroupPatchPath.displayName) {
        throw const FormatException(
          'Required SCIM attributes cannot be removed.',
        );
      }
      if (!hasValue) {
        return AuthScimGroupPatchOperation._(
          kind: kind,
          path: path,
          value: null,
        );
      }
    } else if (!hasValue) {
      throw const FormatException('SCIM patch value is required.');
    }
    final value = switch (path) {
      AuthScimGroupPatchPath.displayName => _requiredPatchString(
        json['value'],
        'displayName',
      ),
      AuthScimGroupPatchPath.externalId => _optionalPatchString(
        json['value'],
        'externalId',
      ),
      AuthScimGroupPatchPath.members => _groupMembers(
        json['value'],
        maximumMembers: maximumMembers,
      ),
    };
    return AuthScimGroupPatchOperation._(kind: kind, path: path, value: value);
  }

  /// Creates an internal validated Group patch operation.
  const AuthScimGroupPatchOperation._({
    required this.kind,
    required this.path,
    required this.value,
  });

  /// Operation semantics.
  final AuthScimPatchOperationKind kind;

  /// Group attribute targeted by the operation.
  final AuthScimGroupPatchPath path;

  /// Typed operation value, when present.
  final Object? value;
}

/// Strict, bounded SCIM Group PatchOp document.
final class AuthScimGroupPatchDocument {
  /// Creates a bounded Group patch document.
  AuthScimGroupPatchDocument({
    required Iterable<AuthScimGroupPatchOperation> operations,
  }) : operations = List<AuthScimGroupPatchOperation>.unmodifiable(operations) {
    if (this.operations.isEmpty || this.operations.length > 32) {
      throw const FormatException('Invalid SCIM patch operation count.');
    }
  }

  /// Decodes and validates a Group PatchOp document.
  factory AuthScimGroupPatchDocument.fromJson(
    Map<String, dynamic> json, {
    int maximumOperations = 32,
    int maximumMembers = 1000,
  }) {
    _onlyKeys(json, const <String>{'schemas', 'Operations'});
    _requireSchemas(json, authScimPatchOperationSchema);
    final raw = json['Operations'];
    if (raw is! List ||
        raw.isEmpty ||
        raw.length > maximumOperations ||
        maximumOperations < 1) {
      throw const FormatException('Invalid SCIM patch operations.');
    }
    return AuthScimGroupPatchDocument(
      operations: raw.map((value) {
        if (value is! Map) {
          throw const FormatException('Invalid SCIM patch operation.');
        }
        return AuthScimGroupPatchOperation.fromJson(
          Map<String, dynamic>.from(value),
          maximumMembers: maximumMembers,
        );
      }),
    );
  }

  /// Operations applied in request order.
  final List<AuthScimGroupPatchOperation> operations;

  /// Applies this document to [current].
  AuthScimGroupData apply(
    AuthScimGroupData current, {
    required int maximumMembers,
  }) {
    var displayName = current.displayName;
    var externalId = current.externalId;
    var members = current.members;
    for (final operation in operations) {
      switch (operation.path) {
        case AuthScimGroupPatchPath.displayName:
          displayName = operation.value! as String;
        case AuthScimGroupPatchPath.externalId:
          externalId = operation.value as String?;
        case AuthScimGroupPatchPath.members:
          final values = operation.value as List<AuthScimGroupMember>?;
          members = switch (operation.kind) {
            AuthScimPatchOperationKind.add => <AuthScimGroupMember>[
              ...members,
              ...?values,
            ],
            AuthScimPatchOperationKind.replace =>
              values ?? const <AuthScimGroupMember>[],
            AuthScimPatchOperationKind.remove =>
              values == null
                  ? const <AuthScimGroupMember>[]
                  : members
                        .where(
                          (member) => !values.any(
                            (removed) =>
                                removed.value == member.value &&
                                removed.type == member.type,
                          ),
                        )
                        .toList(growable: false),
          };
      }
    }
    return AuthScimGroupData(
      displayName: displayName,
      externalId: externalId,
      members: members,
      maximumMembers: maximumMembers,
    );
  }
}

/// Semantics of a direct Group membership mutation.
enum AuthScimGroupMembershipMutationKind {
  /// Adds the supplied members.
  add,

  /// Removes the supplied members.
  remove,

  /// Replaces all members with the supplied set.
  replace,
}

/// Atomic direct-membership mutation requested from an application store.
final class AuthScimGroupMembershipMutation {
  /// Creates an atomic direct-membership mutation.
  AuthScimGroupMembershipMutation({
    required String groupResourceId,
    required this.kind,
    required Iterable<AuthScimGroupMember> members,
    int maximumMembers = 1000,
  }) : groupResourceId = _requiredBounded(
         groupResourceId,
         'groupResourceId',
         256,
       ),
       members = List<AuthScimGroupMember>.unmodifiable(members) {
    _validateGroupMembers(this.members, maximumMembers: maximumMembers);
  }

  /// SCIM Group resource identifier.
  final String groupResourceId;

  /// Membership mutation semantics.
  final AuthScimGroupMembershipMutationKind kind;

  /// Members affected by the mutation.
  final List<AuthScimGroupMember> members;
}

/// SCIM patch operation kind.
enum AuthScimPatchOperationKind {
  /// Adds a value.
  add,

  /// Replaces a value.
  replace,

  /// Removes a value.
  remove,
}

/// User property supported by the bounded typed patch implementation.
enum AuthScimUserPatchPath {
  /// User name.
  userName,

  /// External identifier.
  externalId,

  /// Active lifecycle attribute.
  active,

  /// Display name.
  displayName,

  /// Structured name.
  name,

  /// Email collection.
  emails,
}

/// One validated SCIM user patch operation.
final class AuthScimPatchOperation {
  /// Decodes and validates one User patch operation.
  factory AuthScimPatchOperation.fromJson(Map<String, dynamic> json) {
    _onlyKeys(json, const <String>{'op', 'path', 'value'});
    final rawOp = _requiredString(json, 'op', 16).toLowerCase();
    final kind = switch (rawOp) {
      'add' => AuthScimPatchOperationKind.add,
      'replace' => AuthScimPatchOperationKind.replace,
      'remove' => AuthScimPatchOperationKind.remove,
      _ => throw const FormatException('Invalid SCIM patch operation.'),
    };
    final rawPath = _requiredString(json, 'path', 64).toLowerCase();
    final path = switch (rawPath) {
      'username' => AuthScimUserPatchPath.userName,
      'externalid' => AuthScimUserPatchPath.externalId,
      'active' => AuthScimUserPatchPath.active,
      'displayname' => AuthScimUserPatchPath.displayName,
      'name' => AuthScimUserPatchPath.name,
      'emails' => AuthScimUserPatchPath.emails,
      _ => throw const FormatException('Invalid SCIM patch path.'),
    };
    final hasValue = json.containsKey('value');
    if (kind == AuthScimPatchOperationKind.remove) {
      if (hasValue) {
        throw const FormatException('SCIM remove must not contain value.');
      }
      if (path == AuthScimUserPatchPath.userName ||
          path == AuthScimUserPatchPath.active) {
        throw const FormatException(
          'Required SCIM attributes cannot be removed.',
        );
      }
      return AuthScimPatchOperation._(kind: kind, path: path, value: null);
    }
    if (!hasValue) {
      throw const FormatException('SCIM patch value is required.');
    }
    final value = _patchValue(path, json['value']);
    return AuthScimPatchOperation._(kind: kind, path: path, value: value);
  }

  /// Creates an internal validated User patch operation.
  const AuthScimPatchOperation._({
    required this.kind,
    required this.path,
    required this.value,
  });

  /// Operation semantics.
  final AuthScimPatchOperationKind kind;

  /// User attribute targeted by the operation.
  final AuthScimUserPatchPath path;

  /// Typed operation value, when present.
  final Object? value;
}

/// Strict, bounded SCIM PatchOp document.
final class AuthScimPatchDocument {
  /// Creates a bounded User patch document.
  AuthScimPatchDocument({required Iterable<AuthScimPatchOperation> operations})
    : operations = List<AuthScimPatchOperation>.unmodifiable(operations) {
    if (this.operations.isEmpty || this.operations.length > 32) {
      throw const FormatException('Invalid SCIM patch operation count.');
    }
  }

  /// Decodes and validates a User PatchOp document.
  factory AuthScimPatchDocument.fromJson(
    Map<String, dynamic> json, {
    int maximumOperations = 32,
  }) {
    _onlyKeys(json, const <String>{'schemas', 'Operations'});
    _requireSchemas(json, authScimPatchOperationSchema);
    final raw = json['Operations'];
    if (raw is! List) {
      throw const FormatException('Invalid SCIM patch operations.');
    }
    if (maximumOperations < 1 || raw.length > maximumOperations) {
      throw const FormatException('Invalid SCIM patch operation count.');
    }
    return AuthScimPatchDocument(
      operations: raw.map((value) {
        if (value is! Map) {
          throw const FormatException('Invalid SCIM patch operation.');
        }
        return AuthScimPatchOperation.fromJson(
          Map<String, dynamic>.from(value),
        );
      }),
    );
  }

  /// Operations applied in request order.
  final List<AuthScimPatchOperation> operations;

  /// Applies this validated document to current user data.
  AuthScimUserData apply(AuthScimUserData current) {
    var userName = current.userName;
    var externalId = current.externalId;
    var active = current.active;
    var name = current.name;
    var displayName = current.displayName;
    var emails = current.emails;
    for (final operation in operations) {
      switch (operation.path) {
        case AuthScimUserPatchPath.userName:
          userName = operation.value! as String;
        case AuthScimUserPatchPath.externalId:
          externalId = operation.value as String?;
        case AuthScimUserPatchPath.active:
          active = operation.value! as bool;
        case AuthScimUserPatchPath.displayName:
          displayName = operation.value as String?;
        case AuthScimUserPatchPath.name:
          name = operation.value as AuthScimUserName?;
        case AuthScimUserPatchPath.emails:
          emails = operation.value == null
              ? const <AuthScimUserEmail>[]
              : operation.value! as List<AuthScimUserEmail>;
      }
    }
    return AuthScimUserData(
      userName: userName,
      externalId: externalId,
      active: active,
      name: name,
      displayName: displayName,
      emails: emails,
    );
  }
}

/// Typed ServiceProviderConfig response.
final class AuthScimServiceProviderConfig {
  /// Creates a typed service-provider configuration response.
  const AuthScimServiceProviderConfig({
    required this.maximumPageSize,
    required this.maximumPatchOperations,
  });

  /// Maximum page size accepted by the provider.
  final int maximumPageSize;

  /// Maximum PatchOp operations accepted by the provider.
  final int maximumPatchOperations;

  /// Encodes the SCIM service-provider configuration response.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemas': const <String>[authScimServiceProviderConfigSchema],
    'patch': const <String, Object?>{'supported': true},
    'bulk': const <String, Object?>{
      'supported': false,
      'maxOperations': 0,
      'maxPayloadSize': 0,
    },
    'filter': <String, Object?>{
      'supported': true,
      'maxResults': maximumPageSize,
    },
    'changePassword': const <String, Object?>{'supported': false},
    'sort': const <String, Object?>{'supported': false},
    'etag': const <String, Object?>{'supported': false},
    'authenticationSchemes': const <Object?>[
      <String, Object?>{
        'type': 'oauthbearertoken',
        'name': 'OAuth Bearer Token',
        'description': 'Application-verified bearer token.',
        'primary': true,
      },
    ],
  };
}

/// Typed ResourceType response for the supported SCIM User resource.
final class AuthScimResourceType {
  /// Creates the supported SCIM User resource-type descriptor.
  const AuthScimResourceType();

  /// Encodes the User resource-type response.
  Map<String, Object?> toJson() => const <String, Object?>{
    'schemas': <String>[authScimResourceTypeSchema],
    'id': 'User',
    'name': 'User',
    'endpoint': '/Users',
    'description': 'Provisioned user account.',
    'schema': authScimUserSchema,
    'schemaExtensions': <Object?>[],
  };
}

/// Typed ResourceType response for the supported SCIM Group resource.
final class AuthScimGroupResourceType {
  /// Creates the supported SCIM Group resource-type descriptor.
  const AuthScimGroupResourceType();

  /// Encodes the Group resource-type response.
  Map<String, Object?> toJson() => const <String, Object?>{
    'schemas': <String>[authScimResourceTypeSchema],
    'id': 'Group',
    'name': 'Group',
    'endpoint': '/Groups',
    'description': 'Connection-owned directory group.',
    'schema': authScimGroupSchema,
    'schemaExtensions': <Object?>[],
  };
}

/// Typed Schema response for the bounded core User attributes.
final class AuthScimUserSchemaDefinition {
  /// Creates the bounded SCIM User schema descriptor.
  const AuthScimUserSchemaDefinition();

  /// Encodes the User schema response.
  Map<String, Object?> toJson() => const <String, Object?>{
    'schemas': <String>[authScimSchemaSchema],
    'id': authScimUserSchema,
    'name': 'User',
    'description': 'Routed SCIM core User schema.',
    'attributes': <Object?>[
      <String, Object?>{
        'name': 'userName',
        'type': 'string',
        'multiValued': false,
        'required': true,
        'caseExact': false,
        'mutability': 'readWrite',
        'returned': 'default',
        'uniqueness': 'server',
      },
      <String, Object?>{
        'name': 'externalId',
        'type': 'string',
        'multiValued': false,
        'required': false,
        'caseExact': true,
        'mutability': 'readWrite',
        'returned': 'default',
        'uniqueness': 'none',
      },
      <String, Object?>{
        'name': 'active',
        'type': 'boolean',
        'multiValued': false,
        'required': false,
        'mutability': 'readWrite',
        'returned': 'default',
      },
      <String, Object?>{
        'name': 'displayName',
        'type': 'string',
        'multiValued': false,
        'required': false,
        'mutability': 'readWrite',
        'returned': 'default',
      },
      <String, Object?>{
        'name': 'name',
        'type': 'complex',
        'multiValued': false,
        'required': false,
        'mutability': 'readWrite',
        'returned': 'default',
      },
      <String, Object?>{
        'name': 'emails',
        'type': 'complex',
        'multiValued': true,
        'required': false,
        'mutability': 'readWrite',
        'returned': 'default',
      },
    ],
  };
}

/// Typed Schema response for bounded core Group attributes.
final class AuthScimGroupSchemaDefinition {
  /// Creates the bounded SCIM Group schema descriptor.
  const AuthScimGroupSchemaDefinition();

  /// Encodes the Group schema response.
  Map<String, Object?> toJson() => const <String, Object?>{
    'schemas': <String>[authScimSchemaSchema],
    'id': authScimGroupSchema,
    'name': 'Group',
    'description': 'Routed SCIM core Group schema.',
    'attributes': <Object?>[
      <String, Object?>{
        'name': 'displayName',
        'type': 'string',
        'multiValued': false,
        'required': true,
        'caseExact': false,
        'mutability': 'readWrite',
        'returned': 'default',
        'uniqueness': 'server',
      },
      <String, Object?>{
        'name': 'externalId',
        'type': 'string',
        'multiValued': false,
        'required': false,
        'caseExact': true,
        'mutability': 'readWrite',
        'returned': 'default',
        'uniqueness': 'none',
      },
      <String, Object?>{
        'name': 'members',
        'type': 'complex',
        'multiValued': true,
        'required': false,
        'mutability': 'readWrite',
        'returned': 'default',
        'uniqueness': 'none',
      },
    ],
  };
}

const Map<String, Object?> _authScimSchemasJsonSchema = <String, Object?>{
  'type': 'array',
  'minItems': 1,
  'maxItems': 1,
  'items': <String, Object?>{'const': authScimUserSchema},
};

const Map<String, Object?> _authScimNameJsonSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': <String, Object?>{
    'formatted': <String, Object?>{'type': 'string', 'maxLength': 256},
    'familyName': <String, Object?>{'type': 'string', 'maxLength': 256},
    'givenName': <String, Object?>{'type': 'string', 'maxLength': 256},
    'middleName': <String, Object?>{'type': 'string', 'maxLength': 256},
    'honorificPrefix': <String, Object?>{'type': 'string', 'maxLength': 128},
    'honorificSuffix': <String, Object?>{'type': 'string', 'maxLength': 128},
  },
};

const Map<String, Object?> _authScimEmailJsonSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['value'],
  'properties': <String, Object?>{
    'value': <String, Object?>{
      'type': 'string',
      'minLength': 1,
      'maxLength': 320,
    },
    'type': <String, Object?>{'type': 'string', 'maxLength': 64},
    'display': <String, Object?>{'type': 'string', 'maxLength': 256},
    'primary': <String, Object?>{'type': 'boolean'},
  },
};

const Map<String, Object?> _authScimUserPropertiesJsonSchema =
    <String, Object?>{
      'schemas': _authScimSchemasJsonSchema,
      'externalId': <String, Object?>{'type': 'string', 'maxLength': 256},
      'userName': <String, Object?>{
        'type': 'string',
        'minLength': 1,
        'maxLength': 256,
      },
      'active': <String, Object?>{'type': 'boolean'},
      'displayName': <String, Object?>{'type': 'string', 'maxLength': 256},
      'name': _authScimNameJsonSchema,
      'emails': <String, Object?>{
        'type': 'array',
        'maxItems': 20,
        'items': _authScimEmailJsonSchema,
      },
    };

/// JSON Schema contract for strict SCIM User mutation input.
const Map<String, Object?> authScimUserInputJsonSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['schemas', 'userName'],
  'properties': _authScimUserPropertiesJsonSchema,
};

/// JSON Schema contract for SCIM User responses.
const Map<String, Object?> authScimUserResponseJsonSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['schemas', 'id', 'userName', 'active', 'meta'],
  'properties': <String, Object?>{
    ..._authScimUserPropertiesJsonSchema,
    'id': <String, Object?>{'type': 'string', 'minLength': 1},
    'meta': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['resourceType', 'created', 'lastModified'],
      'properties': <String, Object?>{
        'resourceType': <String, Object?>{'const': 'User'},
        'created': <String, Object?>{'type': 'string', 'format': 'date-time'},
        'lastModified': <String, Object?>{
          'type': 'string',
          'format': 'date-time',
        },
        'location': <String, Object?>{
          'type': 'string',
          'format': 'uri-reference',
        },
        'version': <String, Object?>{'type': 'string', 'maxLength': 256},
      },
    },
  },
};

/// JSON Schema contract for a SCIM ListResponse containing users.
const Map<String, Object?> authScimUserListResponseJsonSchema =
    <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>[
        'schemas',
        'totalResults',
        'startIndex',
        'itemsPerPage',
        'Resources',
      ],
      'properties': <String, Object?>{
        'schemas': <String, Object?>{
          'type': 'array',
          'minItems': 1,
          'maxItems': 1,
          'items': <String, Object?>{'const': authScimListResponseSchema},
        },
        'totalResults': <String, Object?>{'type': 'integer', 'minimum': 0},
        'startIndex': <String, Object?>{'type': 'integer', 'minimum': 1},
        'itemsPerPage': <String, Object?>{'type': 'integer', 'minimum': 0},
        'Resources': <String, Object?>{
          'type': 'array',
          'items': authScimUserResponseJsonSchema,
        },
      },
    };

const Map<String, Object?> _authScimGroupMemberJsonSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['value', 'type'],
  'properties': <String, Object?>{
    'value': <String, Object?>{
      'type': 'string',
      'minLength': 1,
      'maxLength': 256,
    },
    r'$ref': <String, Object?>{
      'type': 'string',
      'format': 'uri-reference',
      'maxLength': 2048,
    },
    'display': <String, Object?>{'type': 'string', 'maxLength': 256},
    'type': <String, Object?>{
      'type': 'string',
      'enum': <String>['User', 'Group'],
    },
  },
};

const Map<String, Object?> _authScimGroupPropertiesJsonSchema =
    <String, Object?>{
      'schemas': <String, Object?>{
        'type': 'array',
        'minItems': 1,
        'maxItems': 1,
        'items': <String, Object?>{'const': authScimGroupSchema},
      },
      'externalId': <String, Object?>{'type': 'string', 'maxLength': 256},
      'displayName': <String, Object?>{
        'type': 'string',
        'minLength': 1,
        'maxLength': 256,
      },
      'members': <String, Object?>{
        'type': 'array',
        'maxItems': 1000,
        'items': _authScimGroupMemberJsonSchema,
      },
    };

/// JSON Schema contract for strict SCIM Group mutation input.
const Map<String, Object?> authScimGroupInputJsonSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['schemas', 'displayName'],
  'properties': _authScimGroupPropertiesJsonSchema,
};

/// JSON Schema contract for SCIM Group responses.
const Map<String, Object?> authScimGroupResponseJsonSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['schemas', 'id', 'displayName', 'meta'],
  'properties': <String, Object?>{
    ..._authScimGroupPropertiesJsonSchema,
    'id': <String, Object?>{'type': 'string', 'minLength': 1},
    'meta': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['resourceType', 'created', 'lastModified'],
      'properties': <String, Object?>{
        'resourceType': <String, Object?>{'const': 'Group'},
        'created': <String, Object?>{'type': 'string', 'format': 'date-time'},
        'lastModified': <String, Object?>{
          'type': 'string',
          'format': 'date-time',
        },
        'location': <String, Object?>{
          'type': 'string',
          'format': 'uri-reference',
        },
        'version': <String, Object?>{'type': 'string', 'maxLength': 256},
      },
    },
  },
};

/// JSON Schema contract for a SCIM ListResponse containing groups.
const Map<String, Object?> authScimGroupListResponseJsonSchema =
    <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>[
        'schemas',
        'totalResults',
        'startIndex',
        'itemsPerPage',
        'Resources',
      ],
      'properties': <String, Object?>{
        'schemas': <String, Object?>{
          'type': 'array',
          'minItems': 1,
          'maxItems': 1,
          'items': <String, Object?>{'const': authScimListResponseSchema},
        },
        'totalResults': <String, Object?>{'type': 'integer', 'minimum': 0},
        'startIndex': <String, Object?>{'type': 'integer', 'minimum': 1},
        'itemsPerPage': <String, Object?>{'type': 'integer', 'minimum': 0},
        'Resources': <String, Object?>{
          'type': 'array',
          'items': authScimGroupResponseJsonSchema,
        },
      },
    };

/// Strict JSON Schema contract for a SCIM Group PatchOp document.
const Map<String, Object?> authScimGroupPatchDocumentJsonSchema =
    <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['schemas', 'Operations'],
      'properties': <String, Object?>{
        'schemas': <String, Object?>{
          'type': 'array',
          'minItems': 1,
          'maxItems': 1,
          'items': <String, Object?>{'const': authScimPatchOperationSchema},
        },
        'Operations': <String, Object?>{
          'type': 'array',
          'minItems': 1,
          'maxItems': 32,
          'items': <String, Object?>{
            'type': 'object',
            'additionalProperties': false,
            'required': <String>['op', 'path'],
            'properties': <String, Object?>{
              'op': <String, Object?>{
                'type': 'string',
                'enum': <String>['add', 'replace', 'remove'],
              },
              'path': <String, Object?>{
                'type': 'string',
                'enum': <String>['displayName', 'externalId', 'members'],
              },
              'value': <String, Object?>{},
            },
          },
        },
      },
    };

/// Strict JSON Schema contract for a SCIM PatchOp document.
const Map<String, Object?> authScimPatchDocumentJsonSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['schemas', 'Operations'],
  'properties': <String, Object?>{
    'schemas': <String, Object?>{
      'type': 'array',
      'minItems': 1,
      'maxItems': 1,
      'items': <String, Object?>{'const': authScimPatchOperationSchema},
    },
    'Operations': <String, Object?>{
      'type': 'array',
      'minItems': 1,
      'maxItems': 32,
      'items': <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['op', 'path'],
        'properties': <String, Object?>{
          'op': <String, Object?>{
            'type': 'string',
            'enum': <String>['add', 'replace', 'remove'],
          },
          'path': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'userName',
              'externalId',
              'active',
              'displayName',
              'name',
              'emails',
            ],
          },
          'value': <String, Object?>{},
        },
      },
    },
  },
};

/// JSON Schema contract for generic, non-secret SCIM errors.
const Map<String, Object?> authScimErrorJsonSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['schemas', 'status', 'detail'],
  'properties': <String, Object?>{
    'schemas': <String, Object?>{
      'type': 'array',
      'minItems': 1,
      'maxItems': 1,
      'items': <String, Object?>{'const': authScimErrorSchema},
    },
    'status': <String, Object?>{'type': 'string', 'pattern': r'^\d{3}$'},
    'scimType': <String, Object?>{
      'type': 'string',
      'enum': <String>['invalidValue', 'uniqueness'],
    },
    'detail': <String, Object?>{'type': 'string', 'maxLength': 256},
  },
};

Object? _patchValue(AuthScimUserPatchPath path, Object? value) {
  switch (path) {
    case AuthScimUserPatchPath.userName:
      if (value is! String) {
        throw const FormatException('Invalid SCIM userName patch value.');
      }
      return _requiredBounded(value, 'userName', 256);
    case AuthScimUserPatchPath.externalId:
    case AuthScimUserPatchPath.displayName:
      if (value is! String) {
        throw const FormatException('Invalid SCIM string patch value.');
      }
      return _bounded(value, 'patch.value', 256);
    case AuthScimUserPatchPath.active:
      if (value is! bool) {
        throw const FormatException('Invalid SCIM active patch value.');
      }
      return value;
    case AuthScimUserPatchPath.name:
      if (value is! Map) {
        throw const FormatException('Invalid SCIM name patch value.');
      }
      return AuthScimUserName.fromJson(Map<String, dynamic>.from(value));
    case AuthScimUserPatchPath.emails:
      return _emails(value);
  }
}

List<AuthScimUserEmail> _emails(Object? value) {
  if (value == null) return const <AuthScimUserEmail>[];
  if (value is! List || value.length > 20) {
    throw const FormatException('Invalid SCIM emails.');
  }
  final result = value
      .map((entry) {
        if (entry is! Map) throw const FormatException('Invalid SCIM email.');
        return AuthScimUserEmail.fromJson(Map<String, dynamic>.from(entry));
      })
      .toList(growable: false);
  _validateEmails(result);
  return result;
}

List<AuthScimGroupMember> _groupMembers(
  Object? value, {
  required int maximumMembers,
}) {
  if (value == null) return const <AuthScimGroupMember>[];
  if (maximumMembers < 0 ||
      maximumMembers > 1000 ||
      value is! List ||
      value.length > maximumMembers) {
    throw const FormatException('Invalid SCIM Group members.');
  }
  final result = value
      .map((entry) {
        if (entry is! Map) {
          throw const FormatException('Invalid SCIM Group member.');
        }
        return AuthScimGroupMember.fromJson(Map<String, dynamic>.from(entry));
      })
      .toList(growable: false);
  _validateGroupMembers(result, maximumMembers: maximumMembers);
  return result;
}

void _validateGroupMembers(
  List<AuthScimGroupMember> members, {
  required int maximumMembers,
}) {
  if (maximumMembers < 0 ||
      maximumMembers > 1000 ||
      members.length > maximumMembers) {
    throw const FormatException('Invalid SCIM Group members.');
  }
  final identities = <String, AuthScimGroupMemberType>{};
  for (final member in members) {
    final previous = identities[member.value];
    if (previous != null) {
      throw const FormatException(
        'Duplicate or conflicting SCIM Group member.',
      );
    }
    identities[member.value] = member.type;
  }
}

String _requiredPatchString(Object? value, String name) {
  if (value is! String) {
    throw const FormatException('Invalid SCIM Group patch value.');
  }
  return _requiredBounded(value, name, 256);
}

String? _optionalPatchString(Object? value, String name) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Invalid SCIM Group patch value.');
  }
  return _bounded(value, name, 256);
}

void _validateEmails(List<AuthScimUserEmail> emails) {
  if (emails.length > 20 || emails.where((value) => value.primary).length > 1) {
    throw const FormatException('Invalid SCIM emails.');
  }
}

T? _optionalObject<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) parse,
) {
  final value = json[key];
  if (value == null) return null;
  if (value is! Map) throw const FormatException('Invalid SCIM object.');
  return parse(Map<String, dynamic>.from(value));
}

void _requireSchemas(Map<String, dynamic> json, String expected) {
  final value = json['schemas'];
  if (value is! List || value.length != 1 || value.single != expected) {
    throw const FormatException('Invalid SCIM schemas.');
  }
}

void _onlyKeys(Map<String, dynamic> json, Set<String> allowed) {
  if (json.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Unknown SCIM attribute.');
  }
}

String _requiredString(Map<String, dynamic> json, String key, int maximum) {
  final value = json[key];
  if (value is! String) {
    throw const FormatException('Invalid SCIM string.');
  }
  return _requiredBounded(value, key, maximum);
}

String? _optionalString(Map<String, dynamic> json, String key, int maximum) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Invalid SCIM string.');
  }
  return _bounded(value, key, maximum);
}

String _requiredBounded(String value, String name, int maximum) {
  final result = _bounded(value, name, maximum);
  if (result.isEmpty) throw FormatException('Invalid SCIM $name.');
  return result;
}

String _bounded(String value, String name, int maximum) {
  final result = value.trim();
  if (result.length > maximum || _containsControl(result)) {
    throw FormatException('Invalid SCIM $name.');
  }
  return result;
}

bool _containsControl(String value) =>
    value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

int _integer(Object? value, {required int fallback}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is String && RegExp(r'^\d+$').hasMatch(value)) {
    return int.tryParse(value) ?? -1;
  }
  throw const FormatException('Invalid SCIM integer.');
}
