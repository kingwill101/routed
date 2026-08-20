/// SCIM 2.0 core User schema identifier.
const String authScimUserSchema = 'urn:ietf:params:scim:schemas:core:2.0:User';

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
enum AuthScimScope { usersRead, usersWrite }

/// Immutable connection identity resolved atomically from one bearer token.
///
/// The application-owned resolver must return the connection and all of its
/// isolation boundaries in one result. Routed performs no secondary tenant or
/// connection lookup after authentication.
final class AuthScimConnectionIdentity {
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

  final String connectionId;
  final String credentialId;
  final String tenantId;
  final String organizationId;
  final String provisioningDomainId;
  final String subjectId;
  final Set<AuthScimScope> scopes;
  final DateTime? expiresAt;

  bool allows(AuthScimScope scope) =>
      scopes.contains(scope) ||
      scope == AuthScimScope.usersRead &&
          scopes.contains(AuthScimScope.usersWrite);

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
  const AuthScimProvisioningContext({required this.connection});

  final AuthScimConnectionIdentity connection;

  String get connectionId => connection.connectionId;
  String get tenantId => connection.tenantId;
  String get organizationId => connection.organizationId;
  String get provisioningDomainId => connection.provisioningDomainId;
  String get subjectId => connection.subjectId;
}

/// Typed SCIM user name.
final class AuthScimUserName {
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

  final String? formatted;
  final String? familyName;
  final String? givenName;
  final String? middleName;
  final String? honorificPrefix;
  final String? honorificSuffix;

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
  AuthScimUserEmail({
    required String value,
    this.type,
    this.display,
    this.primary = false,
  }) : value = _requiredBounded(value, 'email.value', 320) {
    if (type != null) _bounded(type!, 'email.type', 64);
    if (display != null) _bounded(display!, 'email.display', 256);
  }

  final String value;
  final String? type;
  final String? display;
  final bool primary;

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

  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    if (type != null) 'type': type,
    if (display != null) 'display': display,
    if (primary) 'primary': true,
  };
}

/// Strict application-owned data accepted for SCIM User provisioning.
final class AuthScimUserData {
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

  final String userName;
  final String? externalId;
  final bool active;
  final AuthScimUserName? name;
  final String? displayName;
  final List<AuthScimUserEmail> emails;

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
      active: active is bool ? active : true,
      name: _optionalObject(json, 'name', AuthScimUserName.fromJson),
      displayName: _optionalString(json, 'displayName', 256),
      emails: _emails(json['emails']),
    );
  }

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
  AuthScimResourceMeta({
    required DateTime created,
    required DateTime lastModified,
    this.location,
    this.version,
  }) : created = created.toUtc(),
       lastModified = lastModified.toUtc() {
    if (version != null) _bounded(version!, 'version', 256);
  }

  final DateTime created;
  final DateTime lastModified;
  final Uri? location;
  final String? version;

  Map<String, Object?> toJson() => <String, Object?>{
    'resourceType': 'User',
    'created': created.toIso8601String(),
    'lastModified': lastModified.toIso8601String(),
    if (location != null) 'location': location.toString(),
    if (version != null) 'version': version,
  };
}

/// Explicit internal lifecycle of a connection-owned directory user.
enum AuthScimDirectoryUserState { active, inactive, tombstoned }

/// Connection-bound SCIM User resource returned by an application store.
final class AuthScimUser {
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

  final String id;
  final AuthScimUserData data;
  final AuthScimResourceMeta meta;
  final AuthScimDirectoryUserState state;
  final DateTime? tombstonedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    ...data.toJson(),
    'id': id,
    'meta': meta.toJson(),
  };
}

/// Attribute supported by the bounded first-slice SCIM filter parser.
enum AuthScimUserFilterAttribute { id, userName, externalId, email }

/// A bounded SCIM equality filter.
final class AuthScimUserFilter {
  const AuthScimUserFilter({required this.attribute, required this.value});

  final AuthScimUserFilterAttribute attribute;
  final String value;

  static final RegExp _expression = RegExp(
    r'^\s*(id|userName|externalId|emails\.value)\s+eq\s+"((?:[^"\\]|\\["\\])*)"\s*$',
    caseSensitive: false,
  );

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
}

/// Bounded query supplied to [AuthScimProvisioningStore.listUsers].
final class AuthScimListUsersQuery {
  const AuthScimListUsersQuery({
    required this.startIndex,
    required this.count,
    this.filter,
  });

  final int startIndex;
  final int count;
  final AuthScimUserFilter? filter;

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
    return AuthScimListUsersQuery(
      startIndex: startIndex,
      count: requestedCount.clamp(0, maximumPageSize),
      filter: rawFilter == null || rawFilter.trim().isEmpty
          ? null
          : AuthScimUserFilter.parse(rawFilter),
    );
  }
}

/// Tenant-bound page returned by an application provisioning store.
final class AuthScimUserPage {
  AuthScimUserPage({
    required Iterable<AuthScimUser> resources,
    required this.totalResults,
  }) : resources = List<AuthScimUser>.unmodifiable(resources) {
    if (totalResults < 0) {
      throw ArgumentError.value(totalResults, 'totalResults');
    }
  }

  final List<AuthScimUser> resources;
  final int totalResults;
}

/// SCIM patch operation kind.
enum AuthScimPatchOperationKind { add, replace, remove }

/// User property supported by the bounded typed patch implementation.
enum AuthScimUserPatchPath {
  userName,
  externalId,
  active,
  displayName,
  name,
  emails,
}

/// One validated SCIM user patch operation.
final class AuthScimPatchOperation {
  const AuthScimPatchOperation._({
    required this.kind,
    required this.path,
    required this.value,
  });

  final AuthScimPatchOperationKind kind;
  final AuthScimUserPatchPath path;
  final Object? value;

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
}

/// Strict, bounded SCIM PatchOp document.
final class AuthScimPatchDocument {
  AuthScimPatchDocument({required Iterable<AuthScimPatchOperation> operations})
    : operations = List<AuthScimPatchOperation>.unmodifiable(operations) {
    if (this.operations.isEmpty || this.operations.length > 32) {
      throw const FormatException('Invalid SCIM patch operation count.');
    }
  }

  final List<AuthScimPatchOperation> operations;

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
  const AuthScimServiceProviderConfig({
    required this.maximumPageSize,
    required this.maximumPatchOperations,
  });

  final int maximumPageSize;
  final int maximumPatchOperations;

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
  const AuthScimResourceType();

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

/// Typed Schema response for the bounded core User attributes.
final class AuthScimUserSchemaDefinition {
  const AuthScimUserSchemaDefinition();

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
