import 'dart:async';

import 'package:server_auth/src/core/anonymous_store.dart';
import 'package:server_auth/src/core/deletion_transaction.dart';
import 'package:server_auth/src/core/exceptions.dart';
import 'package:server_auth/src/core/models.dart';
import 'package:server_auth/src/core/plugin.dart';
import 'package:server_auth/src/core/rate_limit.dart';
import 'package:server_auth/src/core/tokens.dart'
    show hashOpaqueToken, secureRandomToken;

/// The stable plugin identifier for auth anonymous plugin.
const String authAnonymousPluginId = 'anonymous';

/// Callback that generates auth anonymous name generator.
typedef AuthAnonymousNameGenerator<TContext> =
    FutureOr<String?> Function(TContext context);

/// Result returned by auth anonymous sign in result.
final class AuthAnonymousSignInResult {
  /// Creates an instance of AuthAnonymousSignInResult.
  const AuthAnonymousSignInResult({required this.user});

  /// The user associated with this value.
  final AuthUser user;
}

/// Anonymous authenticated identities that can later be linked to a real
/// sign-in method by the host integration.
final class AnonymousPlugin<TContext>
    implements
        AuthServerPlugin<TContext>,
        AuthEndpointContributor<TContext>,
        AuthPersistenceContributor,
        AuthClientOperationContributor,
        AuthRateLimitContributor,
        AuthUserDeletionPlanContributor {
  /// Creates an instance of AnonymousPlugin.
  AnonymousPlugin({this.generateName, this.disableDeleteAnonymousUser = false});

  /// The generate name associated with this value.
  final AuthAnonymousNameGenerator<TContext>? generateName;

  /// The disable delete anonymous user associated with this value.
  final bool disableDeleteAnonymousUser;

  late AuthAnonymousAccountMutationStore _mutationStore;
  late AuthUserDeletionCoordinator _deletionCoordinator;
  bool _configured = false;

  /// The identifier exposed by this component.
  @override
  String get id => authAnonymousPluginId;

  /// The persistence and data contract exposed by this plugin.
  @override
  AuthServerPluginDataContract get dataContract =>
      const AuthServerPluginDataContract(
        userDataNamespace: authAnonymousPluginId,
      );

  /// Configures the requested value.
  @override
  void configure(AuthServerPluginContext<TContext> context) {
    final host = context.store;
    if (host is! AuthAnonymousAccountMutationStore) {
      throw StateError(
        'AnonymousPlugin requires an AuthAnonymousAccountMutationStore. '
        'Durable topologies must provide a transactional adapter; no '
        'in-memory fallback is installed.',
      );
    }
    if (host is! AuthUserDeletionCoordinatorHost) {
      throw StateError('AnonymousPlugin requires a deletion-coordinator host.');
    }
    _mutationStore = host as AuthAnonymousAccountMutationStore;
    _deletionCoordinator =
        (host as AuthUserDeletionCoordinatorHost).userDeletionCoordinator;
    _configured = true;
  }

  /// The namespace used for plugin-owned user data.
  @override
  String get userDataNamespace => authAnonymousPluginId;

  /// Creates user deletion plan.
  @override
  AuthUserDeletionPlan createUserDeletionPlan(AuthUser user) =>
      AuthNoopUserDeletionPlan(
        domain: _deletionCoordinator.domain,
        userId: user.id,
        namespace: userDataNamespace,
      );

  /// The endpoint descriptors exposed by this plugin.
  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => [
    TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
      id: 'anonymous.signIn',
      method: AuthOperationMethod.post,
      path: const AuthRoutePath('/sign-in/anonymous'),
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authAnonymousPluginId,
            atomicOperationId: 'anonymous.createAccount',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.repeatable,
      ),
      requestCodec: _emptyRequestCodec,
      responseCodec: _authenticationResponseCodec,
      authentication: AuthOperationAuthentication.none,
      rateLimitOperation: const AuthRateLimitOperation('anonymous', 'sign_in'),
      handler: (invocation, request) => _signInEndpoint(invocation),
    ),
    TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
      id: 'anonymous.delete',
      method: AuthOperationMethod.post,
      path: const AuthRoutePath('/delete-anonymous-user'),
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authAnonymousPluginId,
            atomicOperationId: 'anonymous.deleteUser',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.idempotent,
      ),
      requestCodec: _emptyRequestCodec,
      responseCodec: _deletedResponseCodec,
      csrfPolicy: AuthOperationCsrfPolicy.required,
      rateLimitOperation: const AuthRateLimitOperation('anonymous', 'delete'),
      handler: (invocation, request) => _deleteEndpoint(invocation),
    ),
  ];

  /// The client operations exposed by this plugin.
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

  /// The rate-limit operations exposed by this plugin.
  @override
  Iterable<AuthRateLimitOperation> get rateLimitOperations => endpoints
      .map((endpoint) => endpoint.rateLimitOperation)
      .whereType<AuthRateLimitOperation>();

  /// The persistence schemas exposed by this plugin.
  @override
  Iterable<AuthPersistenceSchema> get persistenceSchemas => const [
    AuthPersistenceSchema(
      id: authAnonymousPluginId,
      entities: <AuthEntityDescriptor>[
        AuthEntityDescriptor(
          id: 'user',
          fields: <AuthFieldDescriptor>[
            AuthFieldDescriptor(name: 'isAnonymous', kind: 'boolean'),
          ],
        ),
      ],
      atomicOperations: <AuthAtomicOperationDescriptor>[
        AuthAtomicOperationDescriptor(
          id: 'anonymous.createAccount',
          description:
              'Create one anonymous identity and its replay receipt in a backend transaction.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'anonymous.deleteUser',
          description:
              'Delete the anonymous user through the backend-owned deletion transaction.',
        ),
        AuthAtomicOperationDescriptor(
          id: 'anonymous.completeUpgrade',
          description:
              'Delete an upgraded anonymous identity and record replay completion atomically after host-owned session issuance.',
        ),
      ],
    ),
  ];

  /// Performs the sign in anonymous operation.
  Future<AuthAnonymousSignInResult> signInAnonymous({
    required TContext context,
  }) async {
    _ensureConfigured();
    final userId = secureRandomToken(length: 24);
    final result = await _mutationStore.createAnonymousAccount(
      AuthAnonymousCreateAccountCommand(
        operationId: userId,
        user: AuthUser(
          id: userId,
          name: normalizeAuthAnonymousDisplayName(
            await generateName?.call(context),
          ),
          isAnonymous: true,
        ),
      ),
    );
    if (!result.committed || result.user == null) {
      throw AuthFlowException('anonymous_create_unavailable');
    }
    return AuthAnonymousSignInResult(user: result.user!);
  }

  /// Deletes anonymous user.
  Future<void> deleteAnonymousUser({required AuthUser user}) async {
    _ensureConfigured();
    if (!user.isAnonymous) throw AuthFlowException('anonymous_required');
    if (disableDeleteAnonymousUser) {
      throw AuthFlowException('anonymous_delete_disabled');
    }
    final result = await _mutationStore.deleteAnonymousAccount(
      AuthAnonymousDeleteAccountCommand(
        operationId: hashOpaqueToken('anonymous-delete:${user.id}'),
        userId: user.id,
      ),
    );
    switch (result.status) {
      case AuthAnonymousMutationStatus.applied:
      case AuthAnonymousMutationStatus.replayed:
        return;
      case AuthAnonymousMutationStatus.notAnonymous:
        throw AuthFlowException('anonymous_required');
      case AuthAnonymousMutationStatus.notFound:
        throw AuthFlowException('anonymous_user_not_found');
      case AuthAnonymousMutationStatus.replayMismatch:
        throw AuthFlowException('anonymous_delete_unavailable');
    }
  }

  /// Finalizes an upgrade after the host has issued the target user's session.
  ///
  /// The plugin never creates, serializes, or rolls back that session. A
  /// failed finalization leaves the anonymous identity intact and can be
  /// retried with the same deterministic operation binding.
  Future<void> completeAnonymousAccountUpgrade({
    required AuthUser anonymousUser,
    required AuthUser targetUser,
  }) async {
    _ensureConfigured();
    if (!anonymousUser.isAnonymous) {
      throw AuthFlowException('anonymous_required');
    }
    if (targetUser.isAnonymous || targetUser.id == anonymousUser.id) {
      throw AuthFlowException('anonymous_link_unavailable');
    }
    final result = await _mutationStore.completeAnonymousAccountUpgrade(
      AuthAnonymousCompleteUpgradeCommand(
        operationId: hashOpaqueToken(
          'anonymous-upgrade:${anonymousUser.id}:${targetUser.id}',
        ),
        anonymousUserId: anonymousUser.id,
        targetUserId: targetUser.id,
      ),
    );
    switch (result.status) {
      case AuthAnonymousMutationStatus.applied:
      case AuthAnonymousMutationStatus.replayed:
        return;
      case AuthAnonymousMutationStatus.notAnonymous:
        throw AuthFlowException('anonymous_required');
      case AuthAnonymousMutationStatus.notFound:
      case AuthAnonymousMutationStatus.replayMismatch:
        throw AuthFlowException('anonymous_link_unavailable');
    }
  }

  Future<Object?> _signInEndpoint(
    AuthOperationInvocation<TContext> invocation,
  ) async {
    final result = await signInAnonymous(context: invocation.context);
    return AuthEndpointAuthenticationIntent(
      user: result.user,
      authenticationMethod: 'anonymous',
      metadata: const <String, dynamic>{'status': 'authenticated'},
    );
  }

  Future<Object?> _deleteEndpoint(
    AuthOperationInvocation<TContext> invocation,
  ) async {
    final user = invocation.user;
    if (user == null) throw AuthFlowException('unauthorized');
    await deleteAnonymousUser(user: user);
    await invocation.sessionControl?.signOut();
    return const <String, dynamic>{'status': 'anonymous_deleted'};
  }

  void _ensureConfigured() {
    if (!_configured) throw StateError('AnonymousPlugin is not configured');
  }

  static final AuthOperationCodec<Map<String, dynamic>> _emptyRequestCodec =
      AuthOperationCodec<Map<String, dynamic>>(
        decode: Map<String, dynamic>.from,
        encode: (value) => value,
        schema: const <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
        },
      );

  static final AuthOperationCodec<Object?> _authenticationResponseCodec =
      AuthOperationCodec<Object?>(
        decode: (value) => value,
        encode: (value) => value,
        schema: const <String, Object?>{
          'type': 'object',
          'additionalProperties': true,
          'required': <String>['status', 'user', 'strategy'],
          'properties': <String, Object?>{
            'status': <String, Object?>{'const': 'authenticated'},
            'user': <String, Object?>{'type': 'object'},
            'expires': <String, Object?>{
              'type': <String>['string', 'null'],
              'format': 'date-time',
            },
            'strategy': <String, Object?>{'type': 'string'},
            'token': <String, Object?>{
              'type': 'string',
              'readOnly': true,
              'description':
                  'Present only when JWT response-body exposure is enabled.',
            },
          },
        },
      );

  static final AuthOperationCodec<Object?> _deletedResponseCodec =
      AuthOperationCodec<Object?>(
        decode: (value) => value,
        encode: (value) => value,
        schema: const <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
          'required': <String>['status'],
          'properties': <String, Object?>{
            'status': <String, Object?>{'const': 'anonymous_deleted'},
          },
        },
      );
}
