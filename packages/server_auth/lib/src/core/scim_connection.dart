import 'dart:async';

import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'models.dart';
import 'plugin.dart';
import 'rate_limit.dart';
import 'scim.dart';
import 'scim_connection_models.dart';
import 'scim_connection_store.dart';
import 'scim_models.dart';
import 'tokens.dart' show hashOpaqueToken, secureRandomToken;

/// Stable server-plugin identifier for managed SCIM connections.
const String authScimConnectionPluginId = 'scim_connections';

const String _persistenceSchemaId = 'scim.connections';

typedef AuthScimConnectionTokenGenerator = String Function({int length});

/// Resolver that connects [ScimPlugin] to a managed digest-only store.
final class AuthScimManagedBearerTokenResolver<TContext>
    implements AuthScimBearerTokenResolver<TContext> {
  AuthScimManagedBearerTokenResolver({
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AuthScimConnectionStore store;
  final DateTime Function() _clock;

  @override
  Future<AuthScimConnectionIdentity?> resolve(
    AuthScimBearerTokenRequest<TContext> request,
  ) => Future.sync(
    () => store.resolveCredentialDigest(
      hashOpaqueToken(request.token),
      now: _clock().toUtc(),
    ),
  );
}

/// Plugin-first managed connection and credential administration.
///
/// This plugin is intentionally separate from [ScimPlugin]. Install it only
/// when an application wants a session-authorized management surface, and add
/// its matching client plugin only to clients that administer connections.
final class AuthScimConnectionPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthClientOperationContributor,
        AuthPersistenceContributor,
        AuthRateLimitContributor,
        AuthUserDeletionPlanContributor {
  AuthScimConnectionPlugin({
    required this.store,
    required this.authorize,
    this.tokenPrefix = 'rscim',
    this.defaultCredentialLifetime = const Duration(days: 90),
    this.maximumCredentialLifetime = const Duration(days: 365),
    this.connectionIdGenerator = secureRandomToken,
    this.credentialIdGenerator = secureRandomToken,
    this.secretGenerator = secureRandomToken,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    final prefix = tokenPrefix.trim();
    if (prefix.isEmpty ||
        prefix.length > 16 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(prefix)) {
      throw ArgumentError('Invalid managed SCIM tokenPrefix.');
    }
    if (defaultCredentialLifetime <= Duration.zero ||
        maximumCredentialLifetime < defaultCredentialLifetime) {
      throw ArgumentError('Invalid managed SCIM credential lifetime.');
    }
  }

  final AuthScimConnectionStore store;
  final AuthScimConnectionAuthorizer<TContext> authorize;
  final String tokenPrefix;
  final Duration defaultCredentialLifetime;
  final Duration maximumCredentialLifetime;
  final AuthScimConnectionTokenGenerator connectionIdGenerator;
  final AuthScimConnectionTokenGenerator credentialIdGenerator;
  final AuthScimConnectionTokenGenerator secretGenerator;
  final DateTime Function() _clock;
  late AuthUserDeletionDomain _deletionDomain;

  @override
  String get id => authScimConnectionPluginId;

  @override
  String get userDataNamespace => 'scim_connections';

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    final host = context.store;
    if (host is! AuthUserDeletionCoordinatorHost) {
      throw StateError(
        'AuthScimConnectionPlugin requires a deletion-coordinator host store.',
      );
    }
    _deletionDomain = (host as AuthUserDeletionCoordinatorHost)
        .userDeletionCoordinator
        .domain;
  }

  @override
  Future<AuthUserDeletionPlan> createUserDeletionPlan(AuthUser user) {
    final target = store;
    if (target is AuthUserDeletionPlanFactory) {
      return Future.sync(
        () => (target as AuthUserDeletionPlanFactory).createDeletionPlan(
          domain: _deletionDomain,
          user: user,
          namespace: userDataNamespace,
        ),
      );
    }
    if (_deletionDomain is! AuthInMemoryUserDeletionDomain ||
        target is! AuthInMemoryUserDeletionStore) {
      throw StateError(
        'The managed SCIM adapter has no plan for this persistence domain.',
      );
    }
    return Future.value(
      AuthInMemoryUserDeletionPlan(
        domain: _deletionDomain as AuthInMemoryUserDeletionDomain,
        userId: user.id,
        namespace: userDataNamespace,
        operation: AuthInMemoryStoreDeletionOperation(
          store: target as AuthInMemoryUserDeletionStore,
          userId: user.id,
        ),
      ),
    );
  }

  /// Creates a connection and initial credential in one transaction.
  Future<AuthScimConnectionCreation> create({
    required AuthScimConnectionManagementPrincipal principal,
    required String name,
    required String provisioningDomainId,
    required Iterable<AuthScimScope> scopes,
    required String credentialName,
    required String idempotencyKey,
    DateTime? expiresAt,
  }) async {
    final now = _clock().toUtc();
    final normalizedScopes = _requireScopes(scopes);
    final connectionId = _token(
      connectionIdGenerator(length: 18),
      'connection ID',
    );
    final connection = AuthScimManagedConnection(
      id: connectionId,
      tenantId: principal.tenantId,
      organizationId: principal.organizationId,
      provisioningDomainId: provisioningDomainId,
      subjectId: principal.subjectId,
      name: name,
      scopes: normalizedScopes,
      createdAt: now,
      updatedAt: now,
    );
    final generated = _credential(
      connection: connection,
      name: credentialName,
      scopes: normalizedScopes,
      expiresAt: expiresAt,
      now: now,
    );
    final fingerprint = _fingerprint(<Object?>[
      'create',
      principal.tenantId,
      principal.organizationId,
      principal.subjectId,
      connection.name,
      connection.provisioningDomainId,
      authScimScopeFingerprint(normalizedScopes),
      generated.record.name,
      generated.record.expiresAt?.toIso8601String(),
    ]);
    final stored = await store.createConnection(
      AuthScimCreateConnectionTransaction(
        connection: connection,
        credential: generated.record,
        idempotency: AuthScimIdempotencyBinding(
          key: idempotencyKey,
          fingerprint: fingerprint,
        ),
      ),
    );
    return AuthScimConnectionCreation(
      connection: stored.connection,
      issuance: _issuance(stored.credential, stored.replayed, generated.secret),
    );
  }

  Future<AuthScimConnectionPage> list({
    required AuthScimConnectionManagementPrincipal principal,
    int limit = 100,
    int offset = 0,
  }) => Future.sync(
    () => store.listConnections(
      AuthScimConnectionCatalogQuery(
        binding: principal.binding,
        limit: limit,
        offset: offset,
      ),
    ),
  );

  Future<AuthScimManagedConnection?> update({
    required AuthScimConnectionManagementPrincipal principal,
    required String connectionId,
    required DateTime expectedUpdatedAt,
    required String name,
    required String provisioningDomainId,
    required Iterable<AuthScimScope> scopes,
  }) async {
    final current = await store.findConnection(principal.binding, connectionId);
    if (current == null) return null;
    final next = AuthScimManagedConnection(
      id: current.id,
      tenantId: current.tenantId,
      organizationId: current.organizationId,
      provisioningDomainId: provisioningDomainId,
      subjectId: current.subjectId,
      name: name,
      scopes: _requireScopes(scopes),
      createdAt: current.createdAt,
      updatedAt: _clock().toUtc(),
      disabledAt: current.disabledAt,
    );
    return store.updateConnection(
      AuthScimUpdateConnectionTransaction(
        binding: principal.binding,
        connection: next,
        expectedUpdatedAt: expectedUpdatedAt,
      ),
    );
  }

  Future<AuthScimManagedConnection?> disable({
    required AuthScimConnectionManagementPrincipal principal,
    required String connectionId,
  }) => Future.sync(
    () => store.disableConnection(
      principal.binding,
      connectionId,
      disabledAt: _clock().toUtc(),
    ),
  );

  Future<AuthScimCredentialPage> listCredentials({
    required AuthScimConnectionManagementPrincipal principal,
    required String connectionId,
    int limit = 100,
    int offset = 0,
  }) => Future.sync(
    () => store.listCredentials(
      AuthScimCredentialCatalogQuery(
        binding: principal.binding,
        connectionId: connectionId,
        limit: limit,
        offset: offset,
      ),
      now: _clock().toUtc(),
    ),
  );

  Future<AuthScimCredentialIssuance> issueCredential({
    required AuthScimConnectionManagementPrincipal principal,
    required String connectionId,
    required String name,
    required Iterable<AuthScimScope> scopes,
    required String idempotencyKey,
    DateTime? expiresAt,
  }) async {
    final connection = await store.findConnection(
      principal.binding,
      connectionId,
    );
    if (connection == null) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.notFound,
      );
    }
    final now = _clock().toUtc();
    final normalizedScopes = _requireScopes(scopes);
    final generated = _credential(
      connection: connection,
      name: name,
      scopes: normalizedScopes,
      expiresAt: expiresAt,
      now: now,
    );
    final stored = await store.issueCredential(
      AuthScimIssueCredentialTransaction(
        binding: principal.binding,
        credential: generated.record,
        idempotency: AuthScimIdempotencyBinding(
          key: idempotencyKey,
          fingerprint: _fingerprint(<Object?>[
            'issue',
            principal.tenantId,
            principal.organizationId,
            connection.id,
            generated.record.name,
            authScimScopeFingerprint(normalizedScopes),
            generated.record.expiresAt?.toIso8601String(),
          ]),
        ),
      ),
    );
    return _issuance(stored.credential, stored.replayed, generated.secret);
  }

  Future<AuthScimCredentialIssuance?> rotateCredential({
    required AuthScimConnectionManagementPrincipal principal,
    required String connectionId,
    required String credentialId,
    required String name,
    required Iterable<AuthScimScope> scopes,
    required String idempotencyKey,
    DateTime? expiresAt,
  }) async {
    final connection = await store.findConnection(
      principal.binding,
      connectionId,
    );
    if (connection == null) return null;
    final now = _clock().toUtc();
    final normalizedScopes = _requireScopes(scopes);
    final generated = _credential(
      connection: connection,
      name: name,
      scopes: normalizedScopes,
      expiresAt: expiresAt,
      now: now,
    );
    final stored = await store.rotateCredential(
      AuthScimRotateCredentialTransaction(
        binding: principal.binding,
        connectionId: connection.id,
        credentialId: credentialId,
        replacement: generated.record,
        revokedAt: now,
        idempotency: AuthScimIdempotencyBinding(
          key: idempotencyKey,
          fingerprint: _fingerprint(<Object?>[
            'rotate',
            principal.tenantId,
            principal.organizationId,
            connection.id,
            credentialId.trim(),
            generated.record.name,
            authScimScopeFingerprint(normalizedScopes),
            generated.record.expiresAt?.toIso8601String(),
          ]),
        ),
      ),
    );
    if (stored == null) return null;
    return _issuance(stored.credential, stored.replayed, generated.secret);
  }

  Future<AuthScimCredential?> revokeCredential({
    required AuthScimConnectionManagementPrincipal principal,
    required String connectionId,
    required String credentialId,
  }) async {
    final now = _clock().toUtc();
    final record = await store.revokeCredential(
      principal.binding,
      connectionId,
      credentialId,
      revokedAt: now,
    );
    return record?.toPublic(now: now);
  }

  /// Trusted tenant lifecycle operation. This is deliberately not an endpoint.
  Future<void> deleteTenant(String tenantId) =>
      Future.sync(() => store.deleteForTenant(tenantId));

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints =>
      <AuthEndpointDescriptor<TContext>>[
        _endpoint(
          id: 'scimConnections.list',
          method: AuthOperationMethod.get,
          path: '/scim/connections',
          semantics: const AuthOperationSemantics.readOnly(),
          operation: AuthScimConnectionManagementOperation.list,
          handler: _listEndpoint,
        ),
        _endpoint(
          id: 'scimConnections.create',
          method: AuthOperationMethod.post,
          path: '/scim/connections/create',
          semantics: _atomic(
            'createConnection',
            AuthMutationReplaySafety.idempotent,
          ),
          operation: AuthScimConnectionManagementOperation.create,
          handler: _createEndpoint,
        ),
        _endpoint(
          id: 'scimConnections.update',
          method: AuthOperationMethod.post,
          path: '/scim/connections/update',
          semantics: _atomic(
            'updateConnection',
            AuthMutationReplaySafety.idempotent,
          ),
          operation: AuthScimConnectionManagementOperation.update,
          handler: _updateEndpoint,
        ),
        _endpoint(
          id: 'scimConnections.disable',
          method: AuthOperationMethod.post,
          path: '/scim/connections/disable',
          semantics: _atomic(
            'disableConnection',
            AuthMutationReplaySafety.idempotent,
          ),
          operation: AuthScimConnectionManagementOperation.disable,
          handler: _disableEndpoint,
        ),
        _endpoint(
          id: 'scimConnections.credentials.list',
          method: AuthOperationMethod.get,
          path: '/scim/connections/credentials',
          semantics: const AuthOperationSemantics.readOnly(),
          operation: AuthScimConnectionManagementOperation.credentialsList,
          handler: _listCredentialsEndpoint,
        ),
        _endpoint(
          id: 'scimConnections.credentials.issue',
          method: AuthOperationMethod.post,
          path: '/scim/connections/credentials/issue',
          semantics: _atomic(
            'issueCredential',
            AuthMutationReplaySafety.idempotent,
          ),
          operation: AuthScimConnectionManagementOperation.credentialsIssue,
          handler: _issueCredentialEndpoint,
        ),
        _endpoint(
          id: 'scimConnections.credentials.rotate',
          method: AuthOperationMethod.post,
          path: '/scim/connections/credentials/rotate',
          semantics: _atomic(
            'rotateCredential',
            AuthMutationReplaySafety.idempotent,
          ),
          operation: AuthScimConnectionManagementOperation.credentialsRotate,
          handler: _rotateCredentialEndpoint,
        ),
        _endpoint(
          id: 'scimConnections.credentials.revoke',
          method: AuthOperationMethod.post,
          path: '/scim/connections/credentials/revoke',
          semantics: _atomic(
            'revokeCredential',
            AuthMutationReplaySafety.idempotent,
          ),
          operation: AuthScimConnectionManagementOperation.credentialsRevoke,
          handler: _revokeCredentialEndpoint,
        ),
      ];

  AuthEndpointDescriptor<TContext> _endpoint({
    required String id,
    required AuthOperationMethod method,
    required String path,
    required AuthOperationSemantics semantics,
    required AuthScimConnectionManagementOperation operation,
    required FutureOr<Object?> Function(
      AuthScimConnectionManagementPrincipal principal,
      Map<String, dynamic> request,
    )
    handler,
  }) => TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
    id: id,
    method: method,
    path: path,
    semantics: semantics,
    requestCodec: _requestCodec,
    responseCodec: _responseCodec,
    authentication: AuthOperationAuthentication.session,
    originPolicy: method == AuthOperationMethod.get
        ? AuthOperationOriginPolicy.none
        : AuthOperationOriginPolicy.browser,
    csrfPolicy: method == AuthOperationMethod.get
        ? AuthOperationCsrfPolicy.none
        : AuthOperationCsrfPolicy.required,
    rateLimitOperation: AuthRateLimitOperation(
      authScimConnectionPluginId,
      id.substring('scimConnections.'.length),
    ),
    handler: (invocation, request) async {
      final organizationId = _required(request, 'organizationId', 256);
      final principal = await authorize(
        AuthScimConnectionAuthorizationRequest<TContext>(
          invocation: invocation,
          operation: operation,
          organizationId: organizationId,
        ),
      );
      if (invocation.user == null ||
          principal == null ||
          principal.organizationId != organizationId) {
        throw AuthFlowException('forbidden');
      }
      try {
        return await handler(principal, request);
      } on AuthScimConnectionStoreException catch (error) {
        throw AuthFlowException(_storeError(error.failure));
      } on ArgumentError catch (_) {
        throw AuthFlowException('invalid_request');
      } on FormatException catch (_) {
        throw AuthFlowException('invalid_request');
      }
    },
  );

  Future<Object?> _createEndpoint(
    AuthScimConnectionManagementPrincipal principal,
    Map<String, dynamic> request,
  ) async => (await create(
    principal: principal,
    name: _required(request, 'name', 128),
    provisioningDomainId: _required(request, 'provisioningDomainId', 256),
    scopes: authScimParseScopes(request['scopes']),
    credentialName: _required(request, 'credentialName', 128),
    idempotencyKey: _required(request, 'idempotencyKey', 128),
    expiresAt: _optionalDate(request, 'expiresAt'),
  )).toJson();

  Future<Object?> _listEndpoint(
    AuthScimConnectionManagementPrincipal principal,
    Map<String, dynamic> request,
  ) async => (await list(
    principal: principal,
    limit: _integer(request, 'limit', 100),
    offset: _integer(request, 'offset', 0),
  )).toJson();

  Future<Object?> _updateEndpoint(
    AuthScimConnectionManagementPrincipal principal,
    Map<String, dynamic> request,
  ) async {
    final value = await update(
      principal: principal,
      connectionId: _required(request, 'connectionId', 256),
      expectedUpdatedAt: _date(request, 'expectedUpdatedAt'),
      name: _required(request, 'name', 128),
      provisioningDomainId: _required(request, 'provisioningDomainId', 256),
      scopes: authScimParseScopes(request['scopes']),
    );
    if (value == null) throw AuthFlowException('connection_not_found');
    return value.toJson();
  }

  Future<Object?> _disableEndpoint(
    AuthScimConnectionManagementPrincipal principal,
    Map<String, dynamic> request,
  ) async {
    final value = await disable(
      principal: principal,
      connectionId: _required(request, 'connectionId', 256),
    );
    if (value == null) throw AuthFlowException('connection_not_found');
    return value.toJson();
  }

  Future<Object?> _listCredentialsEndpoint(
    AuthScimConnectionManagementPrincipal principal,
    Map<String, dynamic> request,
  ) async => (await listCredentials(
    principal: principal,
    connectionId: _required(request, 'connectionId', 256),
    limit: _integer(request, 'limit', 100),
    offset: _integer(request, 'offset', 0),
  )).toJson();

  Future<Object?> _issueCredentialEndpoint(
    AuthScimConnectionManagementPrincipal principal,
    Map<String, dynamic> request,
  ) async => (await issueCredential(
    principal: principal,
    connectionId: _required(request, 'connectionId', 256),
    name: _required(request, 'name', 128),
    scopes: authScimParseScopes(request['scopes']),
    idempotencyKey: _required(request, 'idempotencyKey', 128),
    expiresAt: _optionalDate(request, 'expiresAt'),
  )).toJson();

  Future<Object?> _rotateCredentialEndpoint(
    AuthScimConnectionManagementPrincipal principal,
    Map<String, dynamic> request,
  ) async {
    final value = await rotateCredential(
      principal: principal,
      connectionId: _required(request, 'connectionId', 256),
      credentialId: _required(request, 'credentialId', 256),
      name: _required(request, 'name', 128),
      scopes: authScimParseScopes(request['scopes']),
      idempotencyKey: _required(request, 'idempotencyKey', 128),
      expiresAt: _optionalDate(request, 'expiresAt'),
    );
    if (value == null) throw AuthFlowException('credential_not_found');
    return value.toJson();
  }

  Future<Object?> _revokeCredentialEndpoint(
    AuthScimConnectionManagementPrincipal principal,
    Map<String, dynamic> request,
  ) async {
    final value = await revokeCredential(
      principal: principal,
      connectionId: _required(request, 'connectionId', 256),
      credentialId: _required(request, 'credentialId', 256),
    );
    if (value == null) throw AuthFlowException('credential_not_found');
    return value.toJson();
  }

  @override
  Iterable<AuthClientOperationDescriptor> get clientOperations => endpoints.map(
    (endpoint) => AuthClientOperationDescriptor(
      id: endpoint.id,
      method: endpoint.method,
      path: endpoint.path,
      serverOnly: endpoint.serverOnly,
    ),
  );

  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => endpoints
      .map((endpoint) => endpoint.rateLimitOperation)
      .whereType<AuthRateLimitOperation>();

  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: _persistenceSchemaId,
      entities: [
        AuthEntityDescriptor(
          id: 'connection',
          fields: [
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'tenantId', kind: 'id'),
            AuthFieldDescriptor(name: 'organizationId', kind: 'id'),
            AuthFieldDescriptor(name: 'provisioningDomainId', kind: 'id'),
            AuthFieldDescriptor(name: 'subjectId', kind: 'id'),
            AuthFieldDescriptor(name: 'scopes', kind: 'string_set'),
            AuthFieldDescriptor(name: 'disabledAt', kind: 'nullable_datetime'),
          ],
          uniqueConstraints: [
            ['id'],
          ],
          indexes: [
            ['tenantId', 'organizationId'],
            ['subjectId'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'credential',
          fields: [
            AuthFieldDescriptor(name: 'id', kind: 'id'),
            AuthFieldDescriptor(name: 'connectionId', kind: 'id'),
            AuthFieldDescriptor(name: 'secretDigest', kind: 'secret_digest'),
            AuthFieldDescriptor(name: 'scopes', kind: 'string_set'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'nullable_datetime'),
            AuthFieldDescriptor(name: 'revokedAt', kind: 'nullable_datetime'),
          ],
          relationships: [
            AuthRelationshipDescriptor(
              field: 'connectionId',
              targetEntity: 'connection',
              cascadeDelete: true,
            ),
          ],
          uniqueConstraints: [
            ['id'],
            ['secretDigest'],
          ],
          indexes: [
            ['connectionId'],
            ['expiresAt', 'revokedAt'],
          ],
        ),
        AuthEntityDescriptor(
          id: 'replay',
          fields: [
            AuthFieldDescriptor(name: 'binding', kind: 'string'),
            AuthFieldDescriptor(name: 'fingerprint', kind: 'digest'),
            AuthFieldDescriptor(name: 'connectionId', kind: 'id'),
            AuthFieldDescriptor(name: 'credentialId', kind: 'id'),
            AuthFieldDescriptor(name: 'expiresAt', kind: 'datetime'),
          ],
          uniqueConstraints: [
            ['binding'],
          ],
          indexes: [
            ['expiresAt'],
          ],
        ),
      ],
      atomicOperations: [
        AuthAtomicOperationDescriptor(
          id: 'createConnection',
          description:
              'Creates a connection, initial digest-only credential, and replay record.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'updateConnection',
          description:
              'Updates connection metadata and revokes now-invalid credentials.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'disableConnection',
          description: 'Disables a connection and revokes every credential.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'issueCredential',
          description: 'Creates one digest-only credential and replay record.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'rotateCredential',
          description:
              'Revokes one credential and creates its replacement atomically.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'revokeCredential',
          description: 'Idempotently revokes one connection-bound credential.',
        ),
      ],
    ),
  ];

  _GeneratedCredential _credential({
    required AuthScimManagedConnection connection,
    required String name,
    required Set<AuthScimScope> scopes,
    required DateTime? expiresAt,
    required DateTime now,
  }) {
    if (!authScimScopesAllow(connection.scopes, scopes)) {
      throw const AuthScimConnectionStoreException(
        AuthScimConnectionStoreFailure.scopeMismatch,
      );
    }
    final id = _token(credentialIdGenerator(length: 18), 'credential ID');
    final secretPart = _token(secretGenerator(length: 32), 'credential secret');
    final secret = '$tokenPrefix.$id.$secretPart';
    final expiry = _expiry(expiresAt, now);
    return _GeneratedCredential(
      secret: secret,
      record: AuthScimCredentialRecord(
        id: id,
        connectionId: connection.id,
        tenantId: connection.tenantId,
        organizationId: connection.organizationId,
        name: name,
        keyPrefix:
            '$tokenPrefix.${id.substring(0, id.length < 8 ? id.length : 8)}',
        secretDigest: hashOpaqueToken(secret),
        scopes: scopes,
        createdAt: now,
        updatedAt: now,
        expiresAt: expiry,
      ),
    );
  }

  DateTime _expiry(DateTime? requested, DateTime now) {
    final value = (requested ?? now.add(defaultCredentialLifetime)).toUtc();
    if (!value.isAfter(now) ||
        value.isAfter(now.add(maximumCredentialLifetime))) {
      throw ArgumentError('Invalid managed SCIM expiresAt.');
    }
    return value;
  }
}

final class _GeneratedCredential {
  const _GeneratedCredential({required this.record, required this.secret});

  final AuthScimCredentialRecord record;
  final String secret;
}

AuthScimCredentialIssuance _issuance(
  AuthScimCredentialRecord record,
  bool replayed,
  String generatedSecret,
) => AuthScimCredentialIssuance(
  credential: record.toPublic(now: DateTime.now().toUtc()),
  replayed: replayed,
  secret: replayed ? null : generatedSecret,
);

AuthOperationSemantics _atomic(
  String operation,
  AuthMutationReplaySafety replaySafety,
) => AuthOperationSemantics.mutation(
  persistence: AuthMutationPersistence.durable(
    atomicity: AuthMutationAtomicity.atomic,
    reference: AuthPersistenceOperationReference(
      schemaId: _persistenceSchemaId,
      atomicOperationId: operation,
    ),
  ),
  replaySafety: replaySafety,
);

const AuthOperationCodec<Map<String, dynamic>>
_requestCodec = AuthOperationCodec<Map<String, dynamic>>(
  decode: _identityMap,
  encode: _identityMap,
  required: true,
  schema: <String, Object?>{
    r'$id': 'AuthScimConnectionManagementRequest',
    'type': 'object',
    'additionalProperties': true,
    'properties': <String, Object?>{
      'organizationId': <String, Object?>{'type': 'string', 'maxLength': 256},
      'idempotencyKey': <String, Object?>{'type': 'string', 'maxLength': 128},
    },
  },
);

const AuthOperationCodec<Object?> _responseCodec = AuthOperationCodec<Object?>(
  decode: _identityObject,
  encode: _identityObject,
  schema: <String, Object?>{
    r'$id': 'AuthScimConnectionManagementResponse',
    'type': 'object',
    'additionalProperties': true,
  },
);

Map<String, dynamic> _identityMap(Map<String, dynamic> value) => value;
Object? _identityObject(Object? value) => value;

Set<AuthScimScope> _requireScopes(Iterable<AuthScimScope> scopes) {
  final values = Set<AuthScimScope>.unmodifiable(scopes.toSet());
  if (values.isEmpty) throw ArgumentError('SCIM scopes must not be empty.');
  return values;
}

String _token(String value, String name) {
  final normalized = value.trim();
  if (normalized.length < 8 ||
      normalized.length > 256 ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalized)) {
    throw StateError('The $name generator returned an invalid value.');
  }
  return normalized;
}

String _fingerprint(Iterable<Object?> values) =>
    hashOpaqueToken(values.map((value) => value ?? '').join('\u0000'));

String _required(Map<String, dynamic> json, String key, int maximum) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid $key.');
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > maximum ||
      normalized.codeUnits.any((code) => code < 0x20 || code == 0x7f)) {
    throw FormatException('Invalid $key.');
  }
  return normalized;
}

DateTime _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid $key.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid $key.');
  return parsed.toUtc();
}

DateTime? _optionalDate(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _date(json, key);
}

int _integer(Map<String, dynamic> json, String key, int fallback) {
  final value = json[key];
  if (value == null) return fallback;
  final parsed = value is int ? value : int.tryParse('$value');
  if (parsed == null) throw FormatException('Invalid $key.');
  return parsed;
}

String _storeError(AuthScimConnectionStoreFailure failure) => switch (failure) {
  AuthScimConnectionStoreFailure.notFound => 'connection_not_found',
  AuthScimConnectionStoreFailure.disabled => 'connection_disabled',
  AuthScimConnectionStoreFailure.scopeMismatch => 'invalid_scopes',
  AuthScimConnectionStoreFailure.replayMismatch => 'idempotency_conflict',
  AuthScimConnectionStoreFailure.capacity => 'connection_capacity_exhausted',
  AuthScimConnectionStoreFailure.conflict => 'connection_conflict',
};
