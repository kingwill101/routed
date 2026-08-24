import 'dart:async';

import 'package:server_auth/src/core/deletion_transaction.dart';
import 'package:server_auth/src/core/exceptions.dart';
import 'package:server_auth/src/core/models.dart';
import 'package:server_auth/src/core/plugin.dart';
import 'package:server_auth/src/core/rate_limit.dart';
import 'package:server_auth/src/core/scim.dart';
import 'package:server_auth/src/core/scim_connection_models.dart';
import 'package:server_auth/src/core/scim_connection_store.dart';
import 'package:server_auth/src/core/scim_models.dart';
import 'package:server_auth/src/core/tokens.dart'
    show hashOpaqueToken, secureRandomToken;

/// Stable server-plugin identifier for managed SCIM connections.
const String authScimConnectionPluginId = 'scim_connections';

const String _persistenceSchemaId = 'scim.connections';

/// Generates bounded identifiers and secrets for managed SCIM records.
typedef AuthScimConnectionTokenGenerator = String Function({int length});

/// Resolver that connects [ScimPlugin] to a managed digest-only store.
final class AuthScimManagedBearerTokenResolver<TContext>
    implements AuthScimBearerTokenResolver<TContext> {
  /// Creates a resolver backed by [store].
  AuthScimManagedBearerTokenResolver({
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Store containing the digest-only managed credentials.
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
  /// Creates a plugin for managing SCIM connections and credentials.
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

  /// Persistence boundary for connections, credentials, and replay receipts.
  final AuthScimConnectionStore store;

  /// Authorizes each management operation for the current request.
  final AuthScimConnectionAuthorizer<TContext> authorize;

  /// Prefix used for issued managed SCIM bearer tokens.
  final String tokenPrefix;

  /// Lifetime applied when a credential does not specify an expiry.
  final Duration defaultCredentialLifetime;

  /// Maximum lifetime accepted for an issued credential.
  final Duration maximumCredentialLifetime;

  /// Generates connection identifiers.
  final AuthScimConnectionTokenGenerator connectionIdGenerator;

  /// Generates credential identifiers.
  final AuthScimConnectionTokenGenerator credentialIdGenerator;

  /// Generates the raw secret shown when a credential is issued.
  final AuthScimConnectionTokenGenerator secretGenerator;
  final DateTime Function() _clock;
  late AuthUserDeletionDomain _deletionDomain;

  @override
  String get id => authScimConnectionPluginId;

  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract(userDataNamespace: 'scim_connections');

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
      _expiryFingerprint(expiresAt),
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
      issuance: _issuance(
        stored.credential,
        stored.replayed,
        generated.secret,
        now,
      ),
    );
  }

  /// Lists connections visible to [principal].
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

  /// Updates connection metadata using optimistic concurrency control.
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

  /// Disables a connection and revokes its active credentials.
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

  /// Lists credentials belonging to a connection visible to [principal].
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

  /// Issues one credential and returns its raw secret once.
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
            _expiryFingerprint(expiresAt),
          ]),
        ),
      ),
    );
    return _issuance(stored.credential, stored.replayed, generated.secret, now);
  }

  /// Revokes a credential and issues its replacement atomically.
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
            _expiryFingerprint(expiresAt),
          ]),
        ),
      ),
    );
    if (stored == null) return null;
    return _issuance(stored.credential, stored.replayed, generated.secret, now);
  }

  /// Revokes one credential without issuing a replacement.
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
          path: const AuthRoutePath('/scim/connections'),
          semantics: const AuthOperationSemantics.readOnly(),
          operation: AuthScimConnectionManagementOperation.list,
          handler: _listEndpoint,
        ),
        _endpoint(
          id: 'scimConnections.create',
          method: AuthOperationMethod.post,
          path: const AuthRoutePath('/scim/connections/create'),
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
          path: const AuthRoutePath('/scim/connections/update'),
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
          path: const AuthRoutePath('/scim/connections/disable'),
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
          path: const AuthRoutePath('/scim/connections/credentials'),
          semantics: const AuthOperationSemantics.readOnly(),
          operation: AuthScimConnectionManagementOperation.credentialsList,
          handler: _listCredentialsEndpoint,
        ),
        _endpoint(
          id: 'scimConnections.credentials.issue',
          method: AuthOperationMethod.post,
          path: const AuthRoutePath('/scim/connections/credentials/issue'),
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
          path: const AuthRoutePath('/scim/connections/credentials/rotate'),
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
          path: const AuthRoutePath('/scim/connections/credentials/revoke'),
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
    required AuthRoutePath path,
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
    requestCodec: _requestCodecFor(operation),
    responseCodec: _responseCodecFor(operation),
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
      final user = invocation.user;
      if (user == null ||
          principal == null ||
          principal.organizationId != organizationId ||
          principal.subjectId != user.id) {
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
      mount: endpoint.mount,
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

  String _expiryFingerprint(DateTime? requested) => requested == null
      ? 'default:${defaultCredentialLifetime.inSeconds}'
      : requested.toUtc().toIso8601String();
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
  DateTime now,
) => AuthScimCredentialIssuance(
  credential: record.toPublic(now: now),
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

AuthOperationCodec<Map<String, dynamic>> _requestCodecFor(
  AuthScimConnectionManagementOperation operation,
) {
  final properties = <String, Object?>{'organizationId': _stringSchema(256)};
  final required = <String>['organizationId'];
  void add(String name, Map<String, Object?> schema, {bool isRequired = true}) {
    properties[name] = schema;
    if (isRequired) required.add(name);
  }

  switch (operation) {
    case AuthScimConnectionManagementOperation.create:
      add('name', _stringSchema(128));
      add('provisioningDomainId', _stringSchema(256));
      add('scopes', _scopeArraySchema);
      add('credentialName', _stringSchema(128));
      add('idempotencyKey', _stringSchema(128));
      add('expiresAt', _dateSchema, isRequired: false);
    case AuthScimConnectionManagementOperation.list:
      add('limit', _integerSchema(1, 200), isRequired: false);
      add('offset', _integerSchema(0, 1000000), isRequired: false);
    case AuthScimConnectionManagementOperation.update:
      add('connectionId', _stringSchema(256));
      add('expectedUpdatedAt', _dateSchema);
      add('name', _stringSchema(128));
      add('provisioningDomainId', _stringSchema(256));
      add('scopes', _scopeArraySchema);
    case AuthScimConnectionManagementOperation.disable:
      add('connectionId', _stringSchema(256));
    case AuthScimConnectionManagementOperation.credentialsList:
      add('connectionId', _stringSchema(256));
      add('limit', _integerSchema(1, 200), isRequired: false);
      add('offset', _integerSchema(0, 1000000), isRequired: false);
    case AuthScimConnectionManagementOperation.credentialsIssue:
      add('connectionId', _stringSchema(256));
      add('name', _stringSchema(128));
      add('scopes', _scopeArraySchema);
      add('idempotencyKey', _stringSchema(128));
      add('expiresAt', _dateSchema, isRequired: false);
    case AuthScimConnectionManagementOperation.credentialsRotate:
      add('connectionId', _stringSchema(256));
      add('credentialId', _stringSchema(256));
      add('name', _stringSchema(128));
      add('scopes', _scopeArraySchema);
      add('idempotencyKey', _stringSchema(128));
      add('expiresAt', _dateSchema, isRequired: false);
    case AuthScimConnectionManagementOperation.credentialsRevoke:
      add('connectionId', _stringSchema(256));
      add('credentialId', _stringSchema(256));
  }
  return AuthOperationCodec<Map<String, dynamic>>(
    decode: _identityMap,
    encode: _identityMap,
    required: true,
    schema: <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'properties': properties,
      'required': required,
    },
  );
}

AuthOperationCodec<Object?> _responseCodecFor(
  AuthScimConnectionManagementOperation operation,
) => AuthOperationCodec<Object?>(
  decode: _identityObject,
  encode: _identityObject,
  schema: switch (operation) {
    AuthScimConnectionManagementOperation.create => <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'properties': <String, Object?>{
        'connection': _connectionSchema,
        'issuance': _issuanceSchema,
      },
      'required': <String>['connection', 'issuance'],
    },
    AuthScimConnectionManagementOperation.list => _pageSchema(
      _connectionSchema,
    ),
    AuthScimConnectionManagementOperation.update ||
    AuthScimConnectionManagementOperation.disable => _connectionSchema,
    AuthScimConnectionManagementOperation.credentialsList => _pageSchema(
      _credentialSchema,
    ),
    AuthScimConnectionManagementOperation.credentialsIssue ||
    AuthScimConnectionManagementOperation.credentialsRotate => _issuanceSchema,
    AuthScimConnectionManagementOperation.credentialsRevoke =>
      _credentialSchema,
  },
);

Map<String, dynamic> _identityMap(Map<String, dynamic> value) => value;
Object? _identityObject(Object? value) => value;

Map<String, Object?> _stringSchema(int maximum) => <String, Object?>{
  'type': 'string',
  'minLength': 1,
  'maxLength': maximum,
};

Map<String, Object?> _integerSchema(int minimum, int maximum) =>
    <String, Object?>{
      'type': 'integer',
      'minimum': minimum,
      'maximum': maximum,
    };

const Map<String, Object?> _dateSchema = <String, Object?>{
  'type': 'string',
  'format': 'date-time',
};

const Map<String, Object?> _scopeArraySchema = <String, Object?>{
  'type': 'array',
  'minItems': 1,
  'maxItems': 4,
  'uniqueItems': true,
  'items': <String, Object?>{
    'type': 'string',
    'enum': <String>['usersRead', 'usersWrite', 'groupsRead', 'groupsWrite'],
  },
};

final Map<String, Object?> _connectionSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': <String, Object?>{
    'id': _stringSchema(256),
    'tenantId': _stringSchema(256),
    'organizationId': _stringSchema(256),
    'provisioningDomainId': _stringSchema(256),
    'subjectId': _stringSchema(256),
    'name': _stringSchema(128),
    'scopes': _scopeArraySchema,
    'state': <String, Object?>{
      'type': 'string',
      'enum': <String>['active', 'disabled'],
    },
    'createdAt': _dateSchema,
    'updatedAt': _dateSchema,
    'disabledAt': _dateSchema,
  },
  'required': <String>[
    'id',
    'tenantId',
    'organizationId',
    'provisioningDomainId',
    'subjectId',
    'name',
    'scopes',
    'state',
    'createdAt',
    'updatedAt',
  ],
};

final Map<String, Object?> _credentialSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': <String, Object?>{
    'id': _stringSchema(256),
    'connectionId': _stringSchema(256),
    'name': _stringSchema(128),
    'keyPrefix': _stringSchema(32),
    'scopes': _scopeArraySchema,
    'active': <String, Object?>{'type': 'boolean'},
    'createdAt': _dateSchema,
    'updatedAt': _dateSchema,
    'expiresAt': _dateSchema,
    'lastUsedAt': _dateSchema,
    'revokedAt': _dateSchema,
  },
  'required': <String>[
    'id',
    'connectionId',
    'name',
    'keyPrefix',
    'scopes',
    'active',
    'createdAt',
    'updatedAt',
  ],
};

final Map<String, Object?> _issuanceSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'properties': <String, Object?>{
    'credential': _credentialSchema,
    'secret': <String, Object?>{
      'type': 'string',
      'writeOnly': true,
      'description': 'Returned only for the first committed response.',
    },
    'replayed': <String, Object?>{'type': 'boolean'},
  },
  'required': <String>['credential', 'replayed'],
};

Map<String, Object?> _pageSchema(Map<String, Object?> item) =>
    <String, Object?>{
      'type': 'object',
      'additionalProperties': false,
      'properties': <String, Object?>{
        'items': <String, Object?>{'type': 'array', 'items': item},
        'total': _integerSchema(0, 2147483647),
        'limit': _integerSchema(1, 200),
        'offset': _integerSchema(0, 1000000),
      },
      'required': <String>['items', 'total', 'limit', 'offset'],
    };

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
