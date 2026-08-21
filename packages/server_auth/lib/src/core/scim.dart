import 'dart:async';

import 'plugin.dart';
import 'scim_models.dart';

const AuthRouteParameterKey authScimResourceIdRouteParameter =
    AuthRouteParameterKey('id');

/// Stable server-plugin identifier for the SCIM 2.0 provisioning capability.
const String authScimPluginId = 'scim';

/// Media type used by SCIM 2.0 request and response documents.
const String authScimMediaType = 'application/scim+json';

const String _scimPersistenceSchemaId = 'scim.directory';

/// One transient bearer verification request.
final class AuthScimBearerTokenRequest<TContext> {
  const AuthScimBearerTokenRequest({
    required this.context,
    required this.token,
  });

  final TContext context;

  /// Raw token received from the directory.
  ///
  /// It must be digested immediately for lookup and must never be persisted,
  /// logged, returned, or retained by the resolver.
  final String token;
}

/// Application-owned, atomic bearer-token resolution boundary.
///
/// Implementations must look up only a cryptographic digest of the token and,
/// in one atomic operation, validate revocation, expiry, issuer/audience when
/// applicable, and return one immutable connection identity with its exact
/// tenant, organization, provisioning domain, credential, and scopes. Routed
/// never persists or issues bearer credentials.
abstract interface class AuthScimBearerTokenResolver<TContext> {
  FutureOr<AuthScimConnectionIdentity?> resolve(
    AuthScimBearerTokenRequest<TContext> request,
  );
}

/// Application-owned provisioning persistence boundary.
///
/// Every operation receives an exact connection, tenant, organization, and
/// provisioning-domain context. Implementations must enforce all four
/// boundaries again in persistence. Create, replace, patch, uniqueness checks,
/// and tombstoning must each be one atomic store mutation.
///
/// This store owns directory resource truth only. It must not create a sign-in
/// method, grant application access, or infer an auth-user link from email.
/// Applications that project directory state should compose the typed identity
/// and lifecycle capabilities below inside their own safe transaction.
abstract interface class AuthScimProvisioningStore {
  FutureOr<AuthScimUserPage> listUsers(
    AuthScimProvisioningContext context,
    AuthScimListUsersQuery query,
  );

  FutureOr<AuthScimUser?> findUser(
    AuthScimProvisioningContext context,
    String resourceId,
  );

  FutureOr<AuthScimUser> createUser(
    AuthScimProvisioningContext context,
    AuthScimUserData user,
  );

  FutureOr<AuthScimUser?> replaceUser(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimUserData user,
  );

  /// Applies [patch] atomically to the current resource.
  FutureOr<AuthScimUser?> patchUser(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimPatchDocument patch,
  );

  /// Atomically transitions an existing resource to a tombstone.
  ///
  /// Tombstones must remain owned by the exact original connection and must be
  /// excluded from [listUsers] and [findUser]. The returned value is the
  /// committed tombstone, or `null` when no live resource exists.
  FutureOr<AuthScimUser?> tombstoneUser(
    AuthScimProvisioningContext context,
    String resourceId,
  );

  FutureOr<AuthScimGroupPage> listGroups(
    AuthScimProvisioningContext context,
    AuthScimListGroupsQuery query,
  );

  FutureOr<AuthScimGroup?> findGroup(
    AuthScimProvisioningContext context,
    String resourceId,
  );

  FutureOr<AuthScimGroup> createGroup(
    AuthScimProvisioningContext context,
    AuthScimGroupData group,
  );

  FutureOr<AuthScimGroup?> replaceGroup(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimGroupData group,
  );

  /// Applies scalar and direct-membership patch operations atomically.
  FutureOr<AuthScimGroup?> patchGroup(
    AuthScimProvisioningContext context,
    String resourceId,
    AuthScimGroupPatchDocument patch,
  );

  /// Applies one explicit direct-membership mutation atomically.
  ///
  /// The store must validate every referenced SCIM resource against the same
  /// exact connection and tenancy binding. It must reject duplicate or
  /// conflicting references and must not infer application users or roles.
  FutureOr<AuthScimGroup?> mutateGroupMembership(
    AuthScimProvisioningContext context,
    AuthScimGroupMembershipMutation mutation,
  );

  /// Atomically transitions an existing Group resource to a tombstone.
  FutureOr<AuthScimGroup?> tombstoneGroup(
    AuthScimProvisioningContext context,
    String resourceId,
  );
}

/// Signals a persistence uniqueness conflict without exposing store details.
final class AuthScimConflictException implements Exception {
  const AuthScimConflictException();

  @override
  String toString() => 'AuthScimConflictException';
}

/// Sanitized operation context supplied to an optional internal reporter.
final class AuthScimInternalFailure {
  const AuthScimInternalFailure({
    required this.operation,
    required this.error,
    required this.stackTrace,
    this.tenantId,
    this.organizationId,
    this.subjectId,
  });

  final String operation;
  final Object error;
  final StackTrace stackTrace;
  final String? tenantId;
  final String? organizationId;
  final String? subjectId;
}

typedef AuthScimFailureReporter =
    FutureOr<void> Function(AuthScimInternalFailure failure);

/// Bounded SCIM server settings.
final class AuthScimOptions {
  AuthScimOptions({
    this.defaultPageSize = 100,
    this.maximumPageSize = 200,
    this.maximumStartIndex = 1000000,
    this.maximumPatchOperations = 32,
    this.maximumGroupMembers = 1000,
    this.maximumBearerTokenLength = 4096,
  }) {
    if (defaultPageSize < 1 ||
        maximumPageSize < defaultPageSize ||
        maximumPageSize > 1000) {
      throw ArgumentError(
        'SCIM page sizes must satisfy 1 <= default <= maximum <= 1000.',
      );
    }
    if (maximumStartIndex < 1 || maximumStartIndex > 1000000000) {
      throw ArgumentError.value(maximumStartIndex, 'maximumStartIndex');
    }
    if (maximumPatchOperations < 1 || maximumPatchOperations > 32) {
      throw ArgumentError.value(
        maximumPatchOperations,
        'maximumPatchOperations',
      );
    }
    if (maximumGroupMembers < 1 || maximumGroupMembers > 1000) {
      throw ArgumentError.value(maximumGroupMembers, 'maximumGroupMembers');
    }
    if (maximumBearerTokenLength < 32 || maximumBearerTokenLength > 65536) {
      throw ArgumentError.value(
        maximumBearerTokenLength,
        'maximumBearerTokenLength',
      );
    }
  }

  final int defaultPageSize;
  final int maximumPageSize;
  final int maximumStartIndex;
  final int maximumPatchOperations;
  final int maximumGroupMembers;
  final int maximumBearerTokenLength;
}

/// Typed, server-only SCIM 2.0 provisioning plugin.
///
/// The plugin deliberately contributes no Routed auth client plugin. SCIM is
/// consumed by an identity provider using the protocol endpoints directly.
final class ScimPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor {
  ScimPlugin({
    required this.store,
    required this.tokenResolver,
    AuthScimOptions? options,
    this.reportFailure,
  }) : options = options ?? AuthScimOptions();

  final AuthScimProvisioningStore store;
  final AuthScimBearerTokenResolver<TContext> tokenResolver;
  final AuthScimOptions options;
  final AuthScimFailureReporter? reportFailure;

  @override
  String get id => authScimPluginId;

  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract.none();

  @override
  void configure(AuthServerPluginContext<TContext> context) {}

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: _scimPersistenceSchemaId,
      entities: [
        AuthEntityDescriptor(
          id: 'directoryUser',
          fields: [
            AuthFieldDescriptor(name: 'connectionId', kind: 'string'),
            AuthFieldDescriptor(name: 'tenantId', kind: 'string'),
            AuthFieldDescriptor(name: 'organizationId', kind: 'string'),
            AuthFieldDescriptor(name: 'provisioningDomainId', kind: 'string'),
            AuthFieldDescriptor(name: 'resourceId', kind: 'string'),
            AuthFieldDescriptor(name: 'state', kind: 'string'),
          ],
          uniqueConstraints: [
            [
              'connectionId',
              'tenantId',
              'organizationId',
              'provisioningDomainId',
              'resourceId',
            ],
          ],
        ),
        AuthEntityDescriptor(
          id: 'directoryGroup',
          fields: [
            AuthFieldDescriptor(name: 'connectionId', kind: 'string'),
            AuthFieldDescriptor(name: 'tenantId', kind: 'string'),
            AuthFieldDescriptor(name: 'organizationId', kind: 'string'),
            AuthFieldDescriptor(name: 'provisioningDomainId', kind: 'string'),
            AuthFieldDescriptor(name: 'resourceId', kind: 'string'),
            AuthFieldDescriptor(name: 'state', kind: 'string'),
          ],
          uniqueConstraints: [
            [
              'connectionId',
              'tenantId',
              'organizationId',
              'provisioningDomainId',
              'resourceId',
            ],
          ],
        ),
        AuthEntityDescriptor(
          id: 'directoryGroupMember',
          fields: [
            AuthFieldDescriptor(name: 'connectionId', kind: 'string'),
            AuthFieldDescriptor(name: 'tenantId', kind: 'string'),
            AuthFieldDescriptor(name: 'organizationId', kind: 'string'),
            AuthFieldDescriptor(name: 'provisioningDomainId', kind: 'string'),
            AuthFieldDescriptor(name: 'groupResourceId', kind: 'string'),
            AuthFieldDescriptor(name: 'memberResourceId', kind: 'string'),
            AuthFieldDescriptor(name: 'memberType', kind: 'string'),
          ],
          uniqueConstraints: [
            [
              'connectionId',
              'tenantId',
              'organizationId',
              'provisioningDomainId',
              'groupResourceId',
              'memberResourceId',
            ],
          ],
        ),
      ],
      atomicOperations: [
        AuthAtomicOperationDescriptor(
          id: 'createUser',
          description:
              'Creates one directory user after enforcing scoped uniqueness.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'replaceUser',
          description: 'Replaces one live directory user resource.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'patchUser',
          description: 'Applies one bounded patch to one live resource.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'tombstoneUser',
          description: 'Transitions one live directory user to a tombstone.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'createGroup',
          description:
              'Creates one bounded directory Group and its direct members.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'replaceGroup',
          description: 'Replaces one live Group and direct membership set.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'patchGroup',
          description:
              'Applies one bounded Group and membership patch atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'mutateGroupMembership',
          description:
              'Applies one bounded direct-membership mutation atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'tombstoneGroup',
          description: 'Transitions one live directory Group to a tombstone.',
        ),
      ],
    ),
  ];

  @override
  Iterable<AuthEndpointDescriptor<TContext>>
  get endpoints => <AuthEndpointDescriptor<TContext>>[
    _endpoint(
      id: 'scim.serviceProviderConfig',
      method: AuthOperationMethod.get,
      path: const AuthRoutePath('/scim/v2/ServiceProviderConfig'),
      semantics: const AuthOperationSemantics.readOnly(),
      scope: AuthScimScope.usersRead,
      alternateScopes: const <AuthScimScope>{AuthScimScope.groupsRead},
      requestCodec: _emptyRequestCodec,
      responseCodec: _serviceProviderConfigResponseCodec,
      handler: _serviceProviderConfig,
    ),
    _endpoint(
      id: 'scim.resourceTypes',
      method: AuthOperationMethod.get,
      path: const AuthRoutePath('/scim/v2/ResourceTypes'),
      semantics: const AuthOperationSemantics.readOnly(),
      scope: AuthScimScope.usersRead,
      alternateScopes: const <AuthScimScope>{AuthScimScope.groupsRead},
      requestCodec: _emptyRequestCodec,
      responseCodec: _resourceTypesResponseCodec,
      handler: _resourceTypes,
    ),
    _endpoint(
      id: 'scim.schemas',
      method: AuthOperationMethod.get,
      path: const AuthRoutePath('/scim/v2/Schemas'),
      semantics: const AuthOperationSemantics.readOnly(),
      scope: AuthScimScope.usersRead,
      alternateScopes: const <AuthScimScope>{AuthScimScope.groupsRead},
      requestCodec: _emptyRequestCodec,
      responseCodec: _schemasResponseCodec,
      handler: _schemas,
    ),
    _endpoint(
      id: 'scim.users.list',
      method: AuthOperationMethod.get,
      path: const AuthRoutePath('/scim/v2/Users'),
      semantics: const AuthOperationSemantics.readOnly(),
      scope: AuthScimScope.usersRead,
      requestCodec: _listUsersRequestCodec,
      responseCodec: _userListResponseCodec,
      handler: _listUsers,
    ),
    _endpoint(
      id: 'scim.users.get',
      method: AuthOperationMethod.get,
      path: const AuthRoutePath(
        '/scim/v2/Users/{id}',
        parameters: <AuthRouteParameterKey>[authScimResourceIdRouteParameter],
      ),
      semantics: const AuthOperationSemantics.readOnly(),
      scope: AuthScimScope.usersRead,
      requestCodec: _resourceIdRequestCodec,
      responseCodec: _userResponseCodec,
      handler: _getUser,
    ),
    _endpoint(
      id: 'scim.users.create',
      method: AuthOperationMethod.post,
      path: const AuthRoutePath('/scim/v2/Users'),
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: _scimPersistenceSchemaId,
            atomicOperationId: 'createUser',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.unguarded,
      ),
      scope: AuthScimScope.usersWrite,
      requestCodec: _userRequestCodec,
      responseCodec: _userResponseCodec,
      successStatusCode: 201,
      handler: _createUser,
    ),
    _endpoint(
      id: 'scim.users.replace',
      method: AuthOperationMethod.put,
      path: const AuthRoutePath(
        '/scim/v2/Users/{id}',
        parameters: <AuthRouteParameterKey>[authScimResourceIdRouteParameter],
      ),
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: _scimPersistenceSchemaId,
            atomicOperationId: 'replaceUser',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.idempotent,
      ),
      scope: AuthScimScope.usersWrite,
      requestCodec: _userWithIdRequestCodec,
      responseCodec: _userResponseCodec,
      handler: _replaceUser,
    ),
    _endpoint(
      id: 'scim.users.patch',
      method: AuthOperationMethod.patch,
      path: const AuthRoutePath(
        '/scim/v2/Users/{id}',
        parameters: <AuthRouteParameterKey>[authScimResourceIdRouteParameter],
      ),
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: _scimPersistenceSchemaId,
            atomicOperationId: 'patchUser',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.unguarded,
      ),
      scope: AuthScimScope.usersWrite,
      requestCodec: _patchWithIdRequestCodec,
      responseCodec: _userResponseCodec,
      handler: _patchUser,
    ),
    _endpoint(
      id: 'scim.users.delete',
      method: AuthOperationMethod.delete,
      path: const AuthRoutePath(
        '/scim/v2/Users/{id}',
        parameters: <AuthRouteParameterKey>[authScimResourceIdRouteParameter],
      ),
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: _scimPersistenceSchemaId,
            atomicOperationId: 'tombstoneUser',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.idempotent,
      ),
      scope: AuthScimScope.usersWrite,
      requestCodec: _resourceIdRequestCodec,
      responseCodec: _emptyResponseCodec,
      successStatusCode: 204,
      responseHasBody: false,
      handler: _deleteUser,
    ),
    _endpoint(
      id: 'scim.groups.list',
      method: AuthOperationMethod.get,
      path: const AuthRoutePath('/scim/v2/Groups'),
      semantics: const AuthOperationSemantics.readOnly(),
      scope: AuthScimScope.groupsRead,
      requestCodec: _listGroupsRequestCodec,
      responseCodec: _groupListResponseCodec,
      handler: _listGroups,
    ),
    _endpoint(
      id: 'scim.groups.get',
      method: AuthOperationMethod.get,
      path: const AuthRoutePath(
        '/scim/v2/Groups/{id}',
        parameters: <AuthRouteParameterKey>[authScimResourceIdRouteParameter],
      ),
      semantics: const AuthOperationSemantics.readOnly(),
      scope: AuthScimScope.groupsRead,
      requestCodec: _resourceIdRequestCodec,
      responseCodec: _groupResponseCodec,
      handler: _getGroup,
    ),
    _endpoint(
      id: 'scim.groups.create',
      method: AuthOperationMethod.post,
      path: const AuthRoutePath('/scim/v2/Groups'),
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: _scimPersistenceSchemaId,
            atomicOperationId: 'createGroup',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.unguarded,
      ),
      scope: AuthScimScope.groupsWrite,
      requestCodec: _groupRequestCodec,
      responseCodec: _groupResponseCodec,
      successStatusCode: 201,
      handler: _createGroup,
    ),
    _endpoint(
      id: 'scim.groups.replace',
      method: AuthOperationMethod.put,
      path: const AuthRoutePath(
        '/scim/v2/Groups/{id}',
        parameters: <AuthRouteParameterKey>[authScimResourceIdRouteParameter],
      ),
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: _scimPersistenceSchemaId,
            atomicOperationId: 'replaceGroup',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.idempotent,
      ),
      scope: AuthScimScope.groupsWrite,
      requestCodec: _groupWithIdRequestCodec,
      responseCodec: _groupResponseCodec,
      handler: _replaceGroup,
    ),
    _endpoint(
      id: 'scim.groups.patch',
      method: AuthOperationMethod.patch,
      path: const AuthRoutePath(
        '/scim/v2/Groups/{id}',
        parameters: <AuthRouteParameterKey>[authScimResourceIdRouteParameter],
      ),
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: _scimPersistenceSchemaId,
            atomicOperationId: 'patchGroup',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.unguarded,
      ),
      scope: AuthScimScope.groupsWrite,
      requestCodec: _groupPatchWithIdRequestCodec,
      responseCodec: _groupResponseCodec,
      handler: _patchGroup,
    ),
    _endpoint(
      id: 'scim.groups.delete',
      method: AuthOperationMethod.delete,
      path: const AuthRoutePath(
        '/scim/v2/Groups/{id}',
        parameters: <AuthRouteParameterKey>[authScimResourceIdRouteParameter],
      ),
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: _scimPersistenceSchemaId,
            atomicOperationId: 'tombstoneGroup',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.idempotent,
      ),
      scope: AuthScimScope.groupsWrite,
      requestCodec: _resourceIdRequestCodec,
      responseCodec: _emptyResponseCodec,
      successStatusCode: 204,
      responseHasBody: false,
      handler: _deleteGroup,
    ),
  ];

  AuthEndpointDescriptor<TContext> _endpoint({
    required String id,
    required AuthOperationMethod method,
    required AuthRoutePath path,
    required AuthOperationSemantics semantics,
    required AuthScimScope scope,
    Set<AuthScimScope> alternateScopes = const <AuthScimScope>{},
    required AuthOperationCodec<Map<String, dynamic>> requestCodec,
    required AuthOperationCodec<Object?> responseCodec,
    required FutureOr<AuthEndpointHttpResponse> Function(
      AuthScimProvisioningContext context,
      Map<String, dynamic> request,
    )
    handler,
    int successStatusCode = 200,
    bool responseHasBody = true,
  }) => TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
    id: id,
    method: method,
    path: path,
    semantics: semantics,
    requestCodec: requestCodec,
    responseCodec: responseCodec,
    responseContracts: <AuthEndpointResponseContract>[
      AuthEndpointResponseContract(
        statusCode: successStatusCode,
        description: successStatusCode == 201
            ? 'SCIM resource created.'
            : successStatusCode == 204
            ? 'SCIM resource deleted.'
            : 'Successful SCIM response.',
        contract: responseHasBody ? responseCodec : null,
      ),
      for (final status in const <int>[400, 401, 403, 404, 409, 500])
        AuthEndpointResponseContract(
          statusCode: status,
          description: _errorDescription(status),
          contract: _errorResponseCodec,
        ),
    ],
    publicErrorResponse: (kind) => switch (kind) {
      AuthEndpointPublicErrorKind.invalidRequest => _error(
        400,
        'Invalid SCIM request.',
        scimType: 'invalidValue',
      ),
      AuthEndpointPublicErrorKind.internalFailure => _error(
        500,
        'SCIM request failed.',
      ),
    },
    authentication: AuthOperationAuthentication.bearer,
    originPolicy: AuthOperationOriginPolicy.none,
    csrfPolicy: AuthOperationCsrfPolicy.none,
    handler: (invocation, request) => _authorized(
      id,
      invocation,
      request,
      path.parameters,
      <AuthScimScope>{scope, ...alternateScopes},
      handler,
    ),
  );

  Future<AuthEndpointHttpResponse> _authorized(
    String operation,
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> rawRequest,
    Iterable<AuthRouteParameterKey> pathParameters,
    Set<AuthScimScope> scopes,
    FutureOr<AuthEndpointHttpResponse> Function(
      AuthScimProvisioningContext context,
      Map<String, dynamic> request,
    )
    handler,
  ) async {
    final request = Map<String, dynamic>.of(rawRequest);
    for (final parameter in pathParameters) {
      request[parameter.name] = invocation.request.requirePath(parameter);
    }
    final authorization = invocation.request.headers['authorization'];
    AuthScimConnectionIdentity? connection;
    try {
      final token = _bearerToken(authorization);
      if (token == null) return _error(401, 'Unauthorized.');
      connection = await tokenResolver.resolve(
        AuthScimBearerTokenRequest<TContext>(
          context: invocation.context,
          token: token,
        ),
      );
    } catch (error, stackTrace) {
      await _report(
        operation,
        const AuthScimBearerResolutionException(),
        stackTrace,
      );
      return _error(500, 'SCIM request failed.');
    }
    if (connection == null || connection.isExpiredAt(DateTime.now().toUtc())) {
      return _error(401, 'Unauthorized.');
    }
    if (!scopes.any(connection.allows)) {
      return _error(403, 'Insufficient SCIM scope.');
    }
    final provisioningContext = AuthScimProvisioningContext(
      connection: connection,
    );
    try {
      return await handler(provisioningContext, request);
    } on FormatException {
      return _error(400, 'Invalid SCIM request.', scimType: 'invalidValue');
    } on AuthScimConflictException {
      return _error(409, 'SCIM resource conflict.', scimType: 'uniqueness');
    } catch (error, stackTrace) {
      await _report(operation, error, stackTrace, connection: connection);
      return _error(500, 'SCIM request failed.');
    }
  }

  String? _bearerToken(Object? authorization) {
    if (authorization is! String ||
        authorization.length > options.maximumBearerTokenLength + 7 ||
        _containsControl(authorization)) {
      return null;
    }
    final match = RegExp(
      r'^Bearer ([A-Za-z0-9\-._~+/]+=*)$',
      caseSensitive: false,
    ).firstMatch(authorization);
    final token = match?.group(1);
    if (token == null ||
        token.length > options.maximumBearerTokenLength ||
        token.isEmpty) {
      return null;
    }
    return token;
  }

  Future<void> _report(
    String operation,
    Object error,
    StackTrace stackTrace, {
    AuthScimConnectionIdentity? connection,
  }) async {
    final reporter = reportFailure;
    if (reporter == null) return;
    try {
      await reporter(
        AuthScimInternalFailure(
          operation: operation,
          error: error,
          stackTrace: stackTrace,
          tenantId: connection?.tenantId,
          organizationId: connection?.organizationId,
          subjectId: connection?.subjectId,
        ),
      );
    } catch (_) {
      // Reporting must never change the public protocol response.
    }
  }

  AuthEndpointHttpResponse _serviceProviderConfig(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) {
    _requireOnlyKeys(request, const <String>{});
    return _json(
      AuthScimServiceProviderConfig(
        maximumPageSize: options.maximumPageSize,
        maximumPatchOperations: options.maximumPatchOperations,
      ).toJson(),
    );
  }

  AuthEndpointHttpResponse _resourceTypes(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) {
    _requireOnlyKeys(request, const <String>{});
    return _json(
      _listResponse(<Object?>[
        const AuthScimResourceType().toJson(),
        const AuthScimGroupResourceType().toJson(),
      ]),
    );
  }

  AuthEndpointHttpResponse _schemas(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) {
    _requireOnlyKeys(request, const <String>{});
    return _json(
      _listResponse(<Object?>[
        const AuthScimUserSchemaDefinition().toJson(),
        const AuthScimGroupSchemaDefinition().toJson(),
      ]),
    );
  }

  Future<AuthEndpointHttpResponse> _listUsers(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    _requireOnlyKeys(request, const <String>{'startIndex', 'count', 'filter'});
    final query = AuthScimListUsersQuery.fromJson(
      request,
      defaultPageSize: options.defaultPageSize,
      maximumPageSize: options.maximumPageSize,
      maximumStartIndex: options.maximumStartIndex,
    );
    final page = await store.listUsers(context, query);
    if (page.resources.length > query.count ||
        page.totalResults < page.resources.length) {
      throw StateError('SCIM store returned an invalid bounded page.');
    }
    for (final resource in page.resources) {
      _requireBinding(context, resource);
    }
    return _json(<String, Object?>{
      'schemas': const <String>[authScimListResponseSchema],
      'totalResults': page.totalResults,
      'startIndex': query.startIndex,
      'itemsPerPage': page.resources.length,
      'Resources': page.resources
          .map((resource) => resource.toJson())
          .toList(growable: false),
    });
  }

  Future<AuthEndpointHttpResponse> _getUser(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    _requireOnlyKeys(request, const <String>{'id'});
    final resource = await store.findUser(context, _resourceId(request));
    if (resource == null) return _error(404, 'SCIM resource not found.');
    _requireBinding(context, resource);
    return _resourceResponse(resource);
  }

  Future<AuthEndpointHttpResponse> _createUser(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    final resource = await store.createUser(
      context,
      AuthScimUserData.fromJson(request),
    );
    _requireBinding(context, resource);
    return _resourceResponse(resource, statusCode: 201);
  }

  Future<AuthEndpointHttpResponse> _replaceUser(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    final id = _resourceId(request);
    final body = Map<String, dynamic>.of(request)..remove('id');
    final resource = await store.replaceUser(
      context,
      id,
      AuthScimUserData.fromJson(body),
    );
    if (resource == null) return _error(404, 'SCIM resource not found.');
    _requireBinding(context, resource);
    return _resourceResponse(resource);
  }

  Future<AuthEndpointHttpResponse> _patchUser(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    final id = _resourceId(request);
    final body = Map<String, dynamic>.of(request)..remove('id');
    final patch = AuthScimPatchDocument.fromJson(
      body,
      maximumOperations: options.maximumPatchOperations,
    );
    final resource = await store.patchUser(context, id, patch);
    if (resource == null) return _error(404, 'SCIM resource not found.');
    _requireBinding(context, resource);
    return _resourceResponse(resource);
  }

  Future<AuthEndpointHttpResponse> _deleteUser(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    _requireOnlyKeys(request, const <String>{'id'});
    final resource = await store.tombstoneUser(context, _resourceId(request));
    if (resource == null) return _error(404, 'SCIM resource not found.');
    _requireBinding(context, resource, allowTombstone: true);
    if (resource.state != AuthScimDirectoryUserState.tombstoned) {
      throw StateError('SCIM store did not return a tombstone.');
    }
    return _json(null, statusCode: 204);
  }

  Future<AuthEndpointHttpResponse> _listGroups(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    _requireOnlyKeys(request, const <String>{'startIndex', 'count', 'filter'});
    final query = AuthScimListGroupsQuery.fromJson(
      request,
      defaultPageSize: options.defaultPageSize,
      maximumPageSize: options.maximumPageSize,
      maximumStartIndex: options.maximumStartIndex,
    );
    final page = await store.listGroups(context, query);
    if (page.resources.length > query.count ||
        page.totalResults < page.resources.length) {
      throw StateError('SCIM store returned an invalid bounded Group page.');
    }
    for (final resource in page.resources) {
      _requireGroupBinding(context, resource);
    }
    return _json(<String, Object?>{
      'schemas': const <String>[authScimListResponseSchema],
      'totalResults': page.totalResults,
      'startIndex': query.startIndex,
      'itemsPerPage': page.resources.length,
      'Resources': page.resources
          .map((resource) => resource.toJson())
          .toList(growable: false),
    });
  }

  Future<AuthEndpointHttpResponse> _getGroup(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    _requireOnlyKeys(request, const <String>{'id'});
    final resource = await store.findGroup(context, _resourceId(request));
    if (resource == null) return _error(404, 'SCIM resource not found.');
    _requireGroupBinding(context, resource);
    return _groupResourceResponse(resource);
  }

  Future<AuthEndpointHttpResponse> _createGroup(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    final resource = await store.createGroup(
      context,
      AuthScimGroupData.fromJson(
        request,
        maximumMembers: options.maximumGroupMembers,
      ),
    );
    _requireGroupBinding(context, resource);
    return _groupResourceResponse(resource, statusCode: 201);
  }

  Future<AuthEndpointHttpResponse> _replaceGroup(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    final id = _resourceId(request);
    final body = Map<String, dynamic>.of(request)..remove('id');
    final resource = await store.replaceGroup(
      context,
      id,
      AuthScimGroupData.fromJson(
        body,
        maximumMembers: options.maximumGroupMembers,
      ),
    );
    if (resource == null) return _error(404, 'SCIM resource not found.');
    _requireGroupBinding(context, resource);
    return _groupResourceResponse(resource);
  }

  Future<AuthEndpointHttpResponse> _patchGroup(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    final id = _resourceId(request);
    final body = Map<String, dynamic>.of(request)..remove('id');
    final patch = AuthScimGroupPatchDocument.fromJson(
      body,
      maximumOperations: options.maximumPatchOperations,
      maximumMembers: options.maximumGroupMembers,
    );
    final resource = await store.patchGroup(context, id, patch);
    if (resource == null) return _error(404, 'SCIM resource not found.');
    _requireGroupBinding(context, resource);
    return _groupResourceResponse(resource);
  }

  Future<AuthEndpointHttpResponse> _deleteGroup(
    AuthScimProvisioningContext context,
    Map<String, dynamic> request,
  ) async {
    _requireOnlyKeys(request, const <String>{'id'});
    final resource = await store.tombstoneGroup(context, _resourceId(request));
    if (resource == null) return _error(404, 'SCIM resource not found.');
    _requireGroupBinding(context, resource, allowTombstone: true);
    if (resource.state != AuthScimDirectoryGroupState.tombstoned) {
      throw StateError('SCIM store did not return a Group tombstone.');
    }
    return _json(null, statusCode: 204);
  }

  void _requireBinding(
    AuthScimProvisioningContext context,
    AuthScimUser resource, {
    bool allowTombstone = false,
  }) {
    if (resource.connectionId != context.connectionId ||
        resource.tenantId != context.tenantId ||
        resource.organizationId != context.organizationId ||
        resource.provisioningDomainId != context.provisioningDomainId) {
      throw StateError('SCIM store violated its connection boundary.');
    }
    if (!allowTombstone &&
        resource.state == AuthScimDirectoryUserState.tombstoned) {
      throw StateError('SCIM store exposed a tombstoned resource.');
    }
  }

  void _requireGroupBinding(
    AuthScimProvisioningContext context,
    AuthScimGroup resource, {
    bool allowTombstone = false,
  }) {
    if (resource.connectionId != context.connectionId ||
        resource.tenantId != context.tenantId ||
        resource.organizationId != context.organizationId ||
        resource.provisioningDomainId != context.provisioningDomainId) {
      throw StateError('SCIM store violated its Group connection boundary.');
    }
    if (!allowTombstone &&
        resource.state == AuthScimDirectoryGroupState.tombstoned) {
      throw StateError('SCIM store exposed a tombstoned Group resource.');
    }
    if (resource.data.members.length > options.maximumGroupMembers) {
      throw StateError('SCIM store returned an unbounded Group resource.');
    }
  }

  AuthEndpointHttpResponse _resourceResponse(
    AuthScimUser resource, {
    int statusCode = 200,
  }) {
    return _json(
      resource.toJson(),
      statusCode: statusCode,
      headers: <String, String>{
        'Location': ?resource.meta.location?.toString(),
        'ETag': ?resource.meta.version,
      },
    );
  }

  AuthEndpointHttpResponse _groupResourceResponse(
    AuthScimGroup resource, {
    int statusCode = 200,
  }) => _json(
    resource.toJson(),
    statusCode: statusCode,
    headers: <String, String>{
      'Location': ?resource.meta.location?.toString(),
      'ETag': ?resource.meta.version,
    },
  );
}

/// Secret-safe marker reported when application bearer resolution throws.
final class AuthScimBearerResolutionException implements Exception {
  const AuthScimBearerResolutionException();

  @override
  String toString() => 'AuthScimBearerResolutionException';
}

AuthEndpointHttpResponse _json(
  Object? body, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{},
}) => AuthEndpointHttpResponse(
  statusCode: statusCode,
  body: body,
  headers: <String, String>{
    if (body != null) 'Content-Type': authScimMediaType,
    ...headers,
  },
);

AuthEndpointHttpResponse _error(
  int statusCode,
  String detail, {
  String? scimType,
}) => _json(<String, Object?>{
  'schemas': const <String>[authScimErrorSchema],
  'status': statusCode.toString(),
  'scimType': ?scimType,
  'detail': detail,
}, statusCode: statusCode);

Map<String, Object?> _listResponse(List<Object?> resources) =>
    <String, Object?>{
      'schemas': const <String>[authScimListResponseSchema],
      'totalResults': resources.length,
      'startIndex': 1,
      'itemsPerPage': resources.length,
      'Resources': resources,
    };

String _resourceId(Map<String, dynamic> request) {
  final value = request['id'];
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > 256 ||
      _containsControl(value)) {
    throw const FormatException('Invalid SCIM resource ID.');
  }
  return value.trim();
}

void _requireOnlyKeys(Map<String, dynamic> request, Set<String> allowed) {
  if (request.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Unknown SCIM request field.');
  }
}

bool _containsControl(String value) =>
    value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f);

String _errorDescription(int status) => switch (status) {
  400 => 'Invalid SCIM request.',
  401 => 'Bearer authentication failed or is required.',
  403 => 'The service principal lacks the required scope.',
  404 => 'The tenant-scoped SCIM resource was not found.',
  409 => 'The SCIM resource conflicts with an existing resource.',
  _ => 'The SCIM request failed without exposing internal details.',
};

Map<String, dynamic> _identityMap(Map<String, dynamic> value) => value;
Object? _identityObject(Object? value) => value;

const Map<String, Object?> _emptyRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
};

const Map<String, Object?> _resourceIdRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['id'],
  'properties': <String, Object?>{
    'id': <String, Object?>{'type': 'string', 'minLength': 1, 'maxLength': 256},
  },
};

const Map<String, Object?> _listUsersRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': <String, Object?>{
    'startIndex': <String, Object?>{'type': 'integer', 'minimum': 1},
    'count': <String, Object?>{'type': 'integer', 'minimum': 0},
    'filter': <String, Object?>{'type': 'string', 'maxLength': 512},
  },
};

const Map<String, Object?> _listGroupsRequestSchema = _listUsersRequestSchema;

final Map<String, Object?> _userWithIdRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['id', 'schemas', 'userName'],
  'properties': <String, Object?>{
    'id': <String, Object?>{'type': 'string', 'minLength': 1, 'maxLength': 256},
    ...Map<String, Object?>.from(
      authScimUserInputJsonSchema['properties']! as Map,
    ),
  },
};

final Map<String, Object?> _patchWithIdRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['id', 'schemas', 'Operations'],
  'properties': <String, Object?>{
    'id': <String, Object?>{'type': 'string', 'minLength': 1, 'maxLength': 256},
    ...Map<String, Object?>.from(
      authScimPatchDocumentJsonSchema['properties']! as Map,
    ),
  },
};

final Map<String, Object?> _groupWithIdRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['id', 'schemas', 'displayName'],
  'properties': <String, Object?>{
    'id': <String, Object?>{'type': 'string', 'minLength': 1, 'maxLength': 256},
    ...Map<String, Object?>.from(
      authScimGroupInputJsonSchema['properties']! as Map,
    ),
  },
};

final Map<String, Object?> _groupPatchWithIdRequestSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['id', 'schemas', 'Operations'],
  'properties': <String, Object?>{
    'id': <String, Object?>{'type': 'string', 'minLength': 1, 'maxLength': 256},
    ...Map<String, Object?>.from(
      authScimGroupPatchDocumentJsonSchema['properties']! as Map,
    ),
  },
};

const Map<String, Object?> _serviceProviderConfigSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>[
    'schemas',
    'patch',
    'bulk',
    'filter',
    'changePassword',
    'sort',
    'etag',
    'authenticationSchemes',
  ],
  'properties': <String, Object?>{
    'schemas': <String, Object?>{
      'type': 'array',
      'minItems': 1,
      'maxItems': 1,
      'items': <String, Object?>{'const': authScimServiceProviderConfigSchema},
    },
    'patch': _supportedFeatureSchema,
    'bulk': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['supported', 'maxOperations', 'maxPayloadSize'],
      'properties': <String, Object?>{
        'supported': <String, Object?>{'const': false},
        'maxOperations': <String, Object?>{'const': 0},
        'maxPayloadSize': <String, Object?>{'const': 0},
      },
    },
    'filter': <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'required': <String>['supported', 'maxResults'],
      'properties': <String, Object?>{
        'supported': <String, Object?>{'const': true},
        'maxResults': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 1000,
        },
      },
    },
    'changePassword': _unsupportedFeatureSchema,
    'sort': _unsupportedFeatureSchema,
    'etag': _unsupportedFeatureSchema,
    'authenticationSchemes': <String, Object?>{
      'type': 'array',
      'minItems': 1,
      'maxItems': 1,
      'items': <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['type', 'name', 'description', 'primary'],
        'properties': <String, Object?>{
          'type': <String, Object?>{'const': 'oauthbearertoken'},
          'name': <String, Object?>{'type': 'string'},
          'description': <String, Object?>{'type': 'string'},
          'primary': <String, Object?>{'const': true},
        },
      },
    },
  },
};

const Map<String, Object?> _supportedFeatureSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['supported'],
  'properties': <String, Object?>{
    'supported': <String, Object?>{'const': true},
  },
};

const Map<String, Object?> _unsupportedFeatureSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['supported'],
  'properties': <String, Object?>{
    'supported': <String, Object?>{'const': false},
  },
};

const Map<String, Object?> _resourceTypeSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>[
    'schemas',
    'id',
    'name',
    'endpoint',
    'description',
    'schema',
    'schemaExtensions',
  ],
  'properties': <String, Object?>{
    'schemas': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'const': authScimResourceTypeSchema},
    },
    'id': <String, Object?>{
      'enum': <String>['User', 'Group'],
    },
    'name': <String, Object?>{
      'enum': <String>['User', 'Group'],
    },
    'endpoint': <String, Object?>{
      'enum': <String>['/Users', '/Groups'],
    },
    'description': <String, Object?>{'type': 'string'},
    'schema': <String, Object?>{
      'enum': <String>[authScimUserSchema, authScimGroupSchema],
    },
    'schemaExtensions': <String, Object?>{'type': 'array', 'maxItems': 0},
  },
};

const Map<String, Object?> _schemaDefinitionSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': <String>['schemas', 'id', 'name', 'description', 'attributes'],
  'properties': <String, Object?>{
    'schemas': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{'const': authScimSchemaSchema},
    },
    'id': <String, Object?>{
      'enum': <String>[authScimUserSchema, authScimGroupSchema],
    },
    'name': <String, Object?>{
      'enum': <String>['User', 'Group'],
    },
    'description': <String, Object?>{'type': 'string'},
    'attributes': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>[
          'name',
          'type',
          'multiValued',
          'required',
          'mutability',
          'returned',
        ],
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string'},
          'type': <String, Object?>{
            'type': 'string',
            'enum': <String>['string', 'boolean', 'complex'],
          },
          'multiValued': <String, Object?>{'type': 'boolean'},
          'required': <String, Object?>{'type': 'boolean'},
          'caseExact': <String, Object?>{'type': 'boolean'},
          'mutability': <String, Object?>{'const': 'readWrite'},
          'returned': <String, Object?>{'const': 'default'},
          'uniqueness': <String, Object?>{
            'type': 'string',
            'enum': <String>['none', 'server'],
          },
        },
      },
    },
  },
};

const Map<String, Object?> _resourceTypesListSchema = <String, Object?>{
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
      'items': <String, Object?>{'const': authScimListResponseSchema},
    },
    'totalResults': <String, Object?>{'type': 'integer', 'minimum': 0},
    'startIndex': <String, Object?>{'type': 'integer', 'minimum': 1},
    'itemsPerPage': <String, Object?>{'type': 'integer', 'minimum': 0},
    'Resources': <String, Object?>{
      'type': 'array',
      'items': _resourceTypeSchema,
    },
  },
};

const Map<String, Object?> _schemasListSchema = <String, Object?>{
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
      'items': <String, Object?>{'const': authScimListResponseSchema},
    },
    'totalResults': <String, Object?>{'type': 'integer', 'minimum': 0},
    'startIndex': <String, Object?>{'type': 'integer', 'minimum': 1},
    'itemsPerPage': <String, Object?>{'type': 'integer', 'minimum': 0},
    'Resources': <String, Object?>{
      'type': 'array',
      'items': _schemaDefinitionSchema,
    },
  },
};

const AuthOperationCodec<Map<String, dynamic>> _emptyRequestCodec =
    AuthOperationCodec<Map<String, dynamic>>(
      decode: _identityMap,
      encode: _identityMap,
      schema: _emptyRequestSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Map<String, dynamic>> _listUsersRequestCodec =
    AuthOperationCodec<Map<String, dynamic>>(
      decode: _identityMap,
      encode: _identityMap,
      schema: _listUsersRequestSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Map<String, dynamic>> _listGroupsRequestCodec =
    AuthOperationCodec<Map<String, dynamic>>(
      decode: _identityMap,
      encode: _identityMap,
      schema: _listGroupsRequestSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Map<String, dynamic>> _resourceIdRequestCodec =
    AuthOperationCodec<Map<String, dynamic>>(
      decode: _identityMap,
      encode: _identityMap,
      schema: _resourceIdRequestSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Map<String, dynamic>> _userRequestCodec =
    AuthOperationCodec<Map<String, dynamic>>(
      decode: _identityMap,
      encode: _identityMap,
      schema: authScimUserInputJsonSchema,
      contentType: authScimMediaType,
      required: true,
    );
final AuthOperationCodec<Map<String, dynamic>> _userWithIdRequestCodec =
    AuthOperationCodec<Map<String, dynamic>>(
      decode: _identityMap,
      encode: _identityMap,
      schema: _userWithIdRequestSchema,
      contentType: authScimMediaType,
      required: true,
    );
final AuthOperationCodec<Map<String, dynamic>> _patchWithIdRequestCodec =
    AuthOperationCodec<Map<String, dynamic>>(
      decode: _identityMap,
      encode: _identityMap,
      schema: _patchWithIdRequestSchema,
      contentType: authScimMediaType,
      required: true,
    );
const AuthOperationCodec<Map<String, dynamic>> _groupRequestCodec =
    AuthOperationCodec<Map<String, dynamic>>(
      decode: _identityMap,
      encode: _identityMap,
      schema: authScimGroupInputJsonSchema,
      contentType: authScimMediaType,
      required: true,
    );
final AuthOperationCodec<Map<String, dynamic>> _groupWithIdRequestCodec =
    AuthOperationCodec<Map<String, dynamic>>(
      decode: _identityMap,
      encode: _identityMap,
      schema: _groupWithIdRequestSchema,
      contentType: authScimMediaType,
      required: true,
    );
final AuthOperationCodec<Map<String, dynamic>> _groupPatchWithIdRequestCodec =
    AuthOperationCodec<Map<String, dynamic>>(
      decode: _identityMap,
      encode: _identityMap,
      schema: _groupPatchWithIdRequestSchema,
      contentType: authScimMediaType,
      required: true,
    );
const AuthOperationCodec<Object?> _serviceProviderConfigResponseCodec =
    AuthOperationCodec<Object?>(
      decode: _identityMap,
      encode: _identityObject,
      schema: _serviceProviderConfigSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Object?> _resourceTypesResponseCodec =
    AuthOperationCodec<Object?>(
      decode: _identityMap,
      encode: _identityObject,
      schema: _resourceTypesListSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Object?> _schemasResponseCodec =
    AuthOperationCodec<Object?>(
      decode: _identityMap,
      encode: _identityObject,
      schema: _schemasListSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Object?> _userResponseCodec =
    AuthOperationCodec<Object?>(
      decode: _identityMap,
      encode: _identityObject,
      schema: authScimUserResponseJsonSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Object?> _userListResponseCodec =
    AuthOperationCodec<Object?>(
      decode: _identityMap,
      encode: _identityObject,
      schema: authScimUserListResponseJsonSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Object?> _groupResponseCodec =
    AuthOperationCodec<Object?>(
      decode: _identityMap,
      encode: _identityObject,
      schema: authScimGroupResponseJsonSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Object?> _groupListResponseCodec =
    AuthOperationCodec<Object?>(
      decode: _identityMap,
      encode: _identityObject,
      schema: authScimGroupListResponseJsonSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Object?> _errorResponseCodec =
    AuthOperationCodec<Object?>(
      decode: _identityMap,
      encode: _identityObject,
      schema: authScimErrorJsonSchema,
      contentType: authScimMediaType,
    );
const AuthOperationCodec<Object?> _emptyResponseCodec =
    AuthOperationCodec<Object?>(
      decode: _identityMap,
      encode: _identityObject,
      schema: <String, Object?>{},
      contentType: authScimMediaType,
    );
