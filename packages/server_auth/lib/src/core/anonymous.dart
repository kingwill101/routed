import 'dart:async';

import 'deletion_transaction.dart';
import 'exceptions.dart';
import 'plugin.dart';
import 'models.dart';
import 'rate_limit.dart';
import 'store.dart';
import 'tokens.dart' show secureRandomToken;

const String authAnonymousPluginId = 'anonymous';

typedef AuthAnonymousNameGenerator<TContext> =
    FutureOr<String?> Function(TContext context);

typedef AuthAnonymousLinkHandler<TContext> =
    FutureOr<void> Function({
      required TContext context,
      required AuthUser anonymousUser,
      required AuthUser newUser,
    });

final class AuthAnonymousSignInResult {
  const AuthAnonymousSignInResult({required this.user});

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
  AnonymousPlugin({
    this.generateName,
    this.onLinkAccount,
    this.disableDeleteAnonymousUser = false,
  });

  final AuthAnonymousNameGenerator<TContext>? generateName;
  final AuthAnonymousLinkHandler<TContext>? onLinkAccount;
  final bool disableDeleteAnonymousUser;

  late AuthStore _store;
  late AuthUserDeletionCoordinator _deletionCoordinator;
  bool _configured = false;

  @override
  String get id => authAnonymousPluginId;

  @override
  void configure(AuthServerPluginContext<TContext> context) {
    _store = context.store;
    final host = context.store;
    if (host is! AuthUserDeletionCoordinatorHost) {
      throw StateError('AnonymousPlugin requires a deletion-coordinator host.');
    }
    _deletionCoordinator =
        (host as AuthUserDeletionCoordinatorHost).userDeletionCoordinator;
    _configured = true;
  }

  @override
  String get userDataNamespace => authAnonymousPluginId;

  @override
  AuthUserDeletionPlan createUserDeletionPlan(AuthUser user) =>
      AuthNoopUserDeletionPlan(
        domain: _deletionCoordinator.domain,
        userId: user.id,
        namespace: userDataNamespace,
      );

  @override
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints => [
    TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
      id: 'anonymous.signIn',
      method: AuthOperationMethod.post,
      path: '/sign-in/anonymous',
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.nonAtomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authAnonymousPluginId,
          ),
        ),
        replaySafety: AuthMutationReplaySafety.repeatable,
      ),
      requestCodec: _emptyRequestCodec,
      responseCodec: _authenticationResponseCodec,
      authentication: AuthOperationAuthentication.none,
      originPolicy: AuthOperationOriginPolicy.browser,
      csrfPolicy: AuthOperationCsrfPolicy.none,
      rateLimitOperation: const AuthRateLimitOperation('anonymous', 'sign_in'),
      handler: (invocation, request) => _signInEndpoint(invocation),
    ),
    TypedAuthEndpointDescriptor<TContext, Map<String, dynamic>, Object?>(
      id: 'anonymous.delete',
      method: AuthOperationMethod.post,
      path: '/delete-anonymous-user',
      semantics: const AuthOperationSemantics.mutation(
        persistence: AuthMutationPersistence.durable(
          atomicity: AuthMutationAtomicity.atomic,
          reference: AuthPersistenceOperationReference(
            schemaId: authAnonymousPluginId,
            atomicOperationId: 'anonymous.deleteUser',
          ),
        ),
        replaySafety: AuthMutationReplaySafety.singleUse,
      ),
      requestCodec: _emptyRequestCodec,
      responseCodec: _deletedResponseCodec,
      authentication: AuthOperationAuthentication.session,
      originPolicy: AuthOperationOriginPolicy.browser,
      csrfPolicy: AuthOperationCsrfPolicy.required,
      rateLimitOperation: const AuthRateLimitOperation('anonymous', 'delete'),
      handler: (invocation, request) => _deleteEndpoint(invocation),
    ),
  ];

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
          id: 'anonymous.deleteUser',
          description:
              'Delete the anonymous user through the backend-owned deletion transaction.',
        ),
      ],
    ),
  ];

  Future<AuthAnonymousSignInResult> signInAnonymous({
    required TContext context,
  }) async {
    _ensureConfigured();
    final name = await generateName?.call(context);
    final user = await _store.users.create(
      AuthUser(
        id: secureRandomToken(length: 24),
        name: name?.trim().isEmpty == true ? null : name?.trim(),
        isAnonymous: true,
      ),
    );
    return AuthAnonymousSignInResult(user: user);
  }

  Future<void> deleteAnonymousUser({required AuthUser user}) async {
    _ensureConfigured();
    if (!user.isAnonymous) throw AuthFlowException('anonymous_required');
    if (disableDeleteAnonymousUser) {
      throw AuthFlowException('anonymous_delete_disabled');
    }
    if (!await _deletionCoordinator.deleteUser(user.id)) {
      throw AuthFlowException('anonymous_user_not_found');
    }
  }

  /// Runs the host-owned data migration while retaining the anonymous user.
  Future<void> migrateAnonymousAccount({
    required TContext context,
    required AuthUser anonymousUser,
    required AuthUser newUser,
  }) async {
    _ensureConfigured();
    if (!anonymousUser.isAnonymous) {
      throw AuthFlowException('anonymous_required');
    }
    await onLinkAccount?.call(
      context: context,
      anonymousUser: anonymousUser,
      newUser: newUser,
    );
  }

  /// Removes a migrated anonymous identity after replacement sign-in succeeds.
  Future<void> deleteMigratedAnonymousUser(AuthUser anonymousUser) async {
    _ensureConfigured();
    if (!anonymousUser.isAnonymous) {
      throw AuthFlowException('anonymous_required');
    }
    if (!await _deletionCoordinator.deleteUser(anonymousUser.id)) {
      throw AuthFlowException('anonymous_link_unavailable');
    }
  }

  /// Migrates and removes an anonymous account.
  ///
  /// Prefer the split migration/finalization methods when replacement session
  /// issuance can fail between these steps.
  Future<void> linkAnonymousAccount({
    required TContext context,
    required AuthUser anonymousUser,
    required AuthUser newUser,
  }) async {
    await migrateAnonymousAccount(
      context: context,
      anonymousUser: anonymousUser,
      newUser: newUser,
    );
    await deleteMigratedAnonymousUser(anonymousUser);
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
        decode: (value) => Map<String, dynamic>.from(value),
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
