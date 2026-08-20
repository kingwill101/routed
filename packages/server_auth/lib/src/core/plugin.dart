import 'dart:async';

import 'deletion_transaction.dart';
import 'models.dart';
import 'password_hasher.dart';
import 'password_policy.dart';
import 'providers.dart';
import 'rate_limit.dart';
import 'store.dart';

enum AuthOperationMethod { get, post }

enum AuthOperationAuthentication { none, session, apiKey }

enum AuthOperationOriginPolicy { none, browser }

enum AuthOperationCsrfPolicy { none, required }

/// Serialization contract for one side of an auth operation.
///
/// [schema] is JSON Schema Draft 2020-12 metadata. It is optional at runtime,
/// but integrations such as OpenAPI can use it without depending on a
/// framework-specific route type.
abstract interface class AuthOperationContract {
  Map<String, Object?> get schema;
  String get contentType;
  bool get required;
}

final class AuthOperationCodec<T> implements AuthOperationContract {
  const AuthOperationCodec({
    required this.decode,
    required this.encode,
    this.schema = const <String, Object?>{},
    this.contentType = 'application/json',
    this.required = false,
  });

  final T Function(Map<String, dynamic> json) decode;
  final Object? Function(T value) encode;
  @override
  final Map<String, Object?> schema;
  @override
  final String contentType;
  @override
  final bool required;
}

final class AuthOperationInvocation<TContext> {
  const AuthOperationInvocation({
    required this.context,
    required this.user,
    this.emailVerified = false,
    this.activeOrganizationId,
    this.activeTeamId,
    this.writeActiveSelection,
    this.sessionControl,
  });

  final TContext context;
  final AuthUser? user;
  final bool emailVerified;
  final String? activeOrganizationId;
  final String? activeTeamId;
  final FutureOr<void> Function(String? organizationId, String? teamId)?
  writeActiveSelection;
  final AuthServerPluginSessionControl? sessionControl;
}

/// A framework-neutral redirect returned by an auth plugin endpoint.
final class AuthEndpointRedirect {
  const AuthEndpointRedirect({
    required this.location,
    this.statusCode = 302,
    this.headers = const <String, String>{},
  });

  final Uri location;
  final int statusCode;
  final Map<String, String> headers;
}

/// Host-owned session operations available to portable plugin endpoints.
abstract interface class AuthServerPluginSessionControl {
  AuthSessionStrategy get strategy;
  String? get currentSessionId;
  FutureOr<void> signOut();
}

/// Lifecycle phase emitted by the host after it completes an authentication
/// transition or clears one.
enum AuthAuthenticationLifecycleEventType {
  authenticationSucceeded,
  signedOut,
  accountDeleted,
}

/// Typed, in-memory host lifecycle event for optional authentication plugins.
///
/// The event is intentionally not serializable. [authenticationMethod] is a
/// host-owned stable method label, never a credential, token, identifier, or
/// provider response. OAuth hosts may additionally provide the bounded
/// provider namespace in [oauthProviderNamespace].
final class AuthAuthenticationLifecycleEvent<TContext> {
  const AuthAuthenticationLifecycleEvent({
    required this.type,
    required this.context,
    required this.strategy,
    this.authenticationMethod,
    this.oauthProviderNamespace,
  });

  final AuthAuthenticationLifecycleEventType type;
  final TContext context;
  final AuthSessionStrategy strategy;
  final String? authenticationMethod;
  final String? oauthProviderNamespace;
}

/// Optional plugin contributor notified only after host-owned lifecycle work
/// has completed.
abstract interface class AuthAuthenticationLifecycleContributor<TContext> {
  FutureOr<void> onAuthenticationLifecycleEvent(
    AuthAuthenticationLifecycleEvent<TContext> event,
  );
}

enum AuthAuthenticationPolicyPhase { beforeSessionIssue, resolveSession }

final class AuthAuthenticationPolicyRequest<TContext> {
  const AuthAuthenticationPolicyRequest({
    required this.context,
    required this.user,
    required this.phase,
  });

  final TContext context;
  final AuthUser user;
  final AuthAuthenticationPolicyPhase phase;
}

/// Optional plugin contribution consulted at every authentication boundary.
abstract interface class AuthAuthenticationPolicyContributor<TContext> {
  FutureOr<void> enforceAuthenticationPolicy(
    AuthAuthenticationPolicyRequest<TContext> request,
  );
}

/// Credential operation at which an application-owned credential policy runs.
enum AuthCredentialPolicyOperation { signIn, registration }

/// Non-password input supplied to credential policy contributors.
///
/// [verificationToken] is delivery-only request data. It is deliberately not
/// serializable and must not be logged, persisted, or copied into a provider
/// response. The value is supplied only to the policy contributor that needs
/// it, before the credential provider is invoked.
final class AuthCredentialPolicyRequest<TContext> {
  const AuthCredentialPolicyRequest({
    required this.context,
    required this.provider,
    required this.operation,
    this.identifier,
    this.verificationToken,
  });

  final TContext context;
  final AuthProvider provider;
  final AuthCredentialPolicyOperation operation;
  final String? identifier;
  final String? verificationToken;
}

/// Optional policy consulted immediately before a credential provider runs.
abstract interface class AuthCredentialPolicyContributor<TContext> {
  FutureOr<void> enforceCredentialPolicy(
    AuthCredentialPolicyRequest<TContext> request,
  );
}

/// Password mutation protected by an application-owned password policy.
enum AuthPasswordPolicyOperation { registration, passwordReset, passwordChange }

/// Request passed to password policy contributors.
///
/// [password] is a secret and exists only for the duration of the policy
/// call. This type intentionally has no JSON or diagnostic representation.
final class AuthPasswordPolicyRequest<TContext> {
  const AuthPasswordPolicyRequest({
    required this.context,
    required this.operation,
    required this.password,
    this.user,
  });

  final TContext context;
  final AuthPasswordPolicyOperation operation;
  final String password;
  final AuthUser? user;
}

/// Optional policy consulted before a new password is accepted.
abstract interface class AuthPasswordPolicyContributor<TContext> {
  FutureOr<void> enforcePasswordPolicy(
    AuthPasswordPolicyRequest<TContext> request,
  );
}

/// Plugin-owned credentials or tokens that must be revoked when a user is
/// made unavailable without deleting their data.
abstract interface class AuthUserAccessRevocationContributor {
  String get userAccessNamespace;
  FutureOr<void> revokeUserAccess(String userId);
}

/// Optional second-pass composition after every plugin has been registered.
abstract interface class AuthServerPluginTopologyAware<TContext> {
  void composePluginTopology(Iterable<AuthServerPlugin<TContext>> plugins);
}

typedef AuthOAuthTokenGrantHandler<TContext> =
    FutureOr<Object?> Function(
      AuthOperationInvocation<TContext> invocation,
      Map<String, dynamic> request,
    );

/// Host for grant handlers sharing a single OAuth token endpoint.
abstract interface class AuthOAuthTokenEndpointHost<TContext> {
  void registerOAuthTokenGrant(
    String grantType,
    AuthOAuthTokenGrantHandler<TContext> handler,
  );
}

abstract interface class AuthEndpointDescriptor<TContext> {
  String get id;
  AuthOperationMethod get method;
  String get path;
  AuthOperationAuthentication get authentication;
  AuthOperationOriginPolicy get originPolicy;
  AuthOperationCsrfPolicy get csrfPolicy;
  AuthRateLimitOperation? get rateLimitOperation;
  bool get serverOnly;

  FutureOr<Object?> invoke(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  );
}

/// Optional endpoint contribution used to derive a private rate-limit key.
///
/// The returned value is supplied only to [AuthRateLimiter]. Implementations
/// must return a canonical non-secret identifier and must never return a
/// password, captcha token, bearer credential, or other request secret.
abstract interface class AuthEndpointRateLimitIdentifierDescriptor {
  /// Decodes [input], derives an endpoint-specific key, and applies the common
  /// limiter-identifier safety boundary.
  ///
  /// Invalid endpoint input produces no identifier. The endpoint invocation
  /// still performs normal request decoding and returns its normal public
  /// validation error.
  String? resolveRateLimitIdentifier(Map<String, dynamic> input);
}

/// Derives a private limiter key from a successfully decoded endpoint request.
typedef AuthEndpointRateLimitIdentifierResolver<TRequest> =
    String? Function(TRequest request);

typedef AuthEndpointAuthenticationProjector =
    FutureOr<Object?> Function(Map<String, dynamic> sessionPayload);

/// A successful plugin authentication that must be completed by the host.
///
/// Portable plugins verify credentials and describe the identity transition,
/// but they never issue or serialize a session. Framework integrations must
/// apply their central authentication policy, issue the configured session
/// strategy, run callbacks and lifecycle events, and only then call
/// [projectResponse] with the host-owned public session payload.
final class AuthEndpointAuthenticationIntent {
  AuthEndpointAuthenticationIntent({
    required this.user,
    required this.authenticationMethod,
    this.provider,
    this.maximumAge,
    this.impersonatedBy,
    Map<String, dynamic> metadata = const <String, dynamic>{},
    AuthEndpointAuthenticationProjector? projectResponse,
  }) : metadata = Map<String, dynamic>.unmodifiable(
         _validateAuthenticationMetadata(metadata),
       ),
       _projectResponse = projectResponse {
    if (authenticationMethod.trim().isEmpty) {
      throw ArgumentError.value(
        authenticationMethod,
        'authenticationMethod',
        'must not be empty',
      );
    }
  }

  final AuthUser user;
  final String authenticationMethod;
  final AuthProvider? provider;
  final Duration? maximumAge;
  final String? impersonatedBy;
  final Map<String, dynamic> metadata;
  final AuthEndpointAuthenticationProjector? _projectResponse;

  FutureOr<Object?> projectResponse(Map<String, dynamic> sessionPayload) {
    final projector = _projectResponse;
    if (projector != null) return projector(sessionPayload);
    return <String, dynamic>{...metadata, ...sessionPayload};
  }
}

const Set<String> _authSessionPayloadKeys = <String>{
  'user',
  'expires',
  'strategy',
  'token',
};

Map<String, dynamic> _validateAuthenticationMetadata(
  Map<String, dynamic> metadata,
) {
  final reserved = metadata.keys.where(_authSessionPayloadKeys.contains);
  if (reserved.isNotEmpty) {
    throw ArgumentError.value(
      metadata,
      'metadata',
      'must not define host-owned session fields: ${reserved.join(', ')}',
    );
  }
  return metadata;
}

/// Optional typed request/response contracts exposed by an auth endpoint.
///
/// Keeping this separate from [AuthEndpointDescriptor] preserves custom
/// untyped endpoint implementations while allowing typed endpoints to drive
/// documentation and generated clients.
abstract interface class AuthEndpointContractDescriptor {
  AuthOperationContract get requestCodec;
  AuthOperationContract get responseCodec;
}

final class TypedAuthEndpointDescriptor<TContext, TRequest, TResponse>
    implements
        AuthEndpointDescriptor<TContext>,
        AuthEndpointContractDescriptor,
        AuthEndpointRateLimitIdentifierDescriptor {
  const TypedAuthEndpointDescriptor({
    required this.id,
    required this.method,
    required this.path,
    required this.requestCodec,
    required this.responseCodec,
    required this.handler,
    this.authentication = AuthOperationAuthentication.session,
    this.originPolicy = AuthOperationOriginPolicy.browser,
    this.csrfPolicy = AuthOperationCsrfPolicy.none,
    this.rateLimitOperation,
    this.rateLimitIdentifier,
    this.serverOnly = false,
  });

  @override
  final String id;
  @override
  final AuthOperationMethod method;
  @override
  final String path;
  @override
  final AuthOperationCodec<TRequest> requestCodec;
  @override
  final AuthOperationCodec<TResponse> responseCodec;
  final FutureOr<TResponse> Function(
    AuthOperationInvocation<TContext> invocation,
    TRequest request,
  )
  handler;
  @override
  final AuthOperationAuthentication authentication;
  @override
  final AuthOperationOriginPolicy originPolicy;
  @override
  final AuthOperationCsrfPolicy csrfPolicy;
  @override
  final AuthRateLimitOperation? rateLimitOperation;
  final AuthEndpointRateLimitIdentifierResolver<TRequest>? rateLimitIdentifier;
  @override
  final bool serverOnly;

  @override
  String? resolveRateLimitIdentifier(Map<String, dynamic> input) {
    final resolver = rateLimitIdentifier;
    if (resolver == null) return null;
    try {
      return normalizeAuthRateLimitIdentifier(
        resolver(requestCodec.decode(input)),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Object?> invoke(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    final response = await handler(invocation, requestCodec.decode(input));
    return responseCodec.encode(response);
  }
}

abstract interface class AuthEndpointContributor<TContext> {
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints;
}

/// Public endpoint contracts implemented by the framework host.
///
/// These descriptors are included in documentation and generated clients but
/// are deliberately kept out of [AuthEndpointContributor.endpoints], because
/// the host owns their transport behavior and must not mount them through the
/// generic plugin invocation path.
abstract interface class AuthHostEndpointContributor<TContext> {
  Iterable<AuthEndpointDescriptor<TContext>> get hostEndpoints;
}

abstract interface class AuthPersistenceContributor {
  Iterable<AuthPersistenceSchema> get persistenceSchemas;
}

abstract interface class AuthClientOperationContributor {
  Iterable<AuthClientOperationDescriptor> get clientOperations;
}

abstract interface class AuthRateLimitContributor {
  Iterable<AuthRateLimitOperation> get rateLimitOperations;
}

final class AuthClientOperationDescriptor {
  const AuthClientOperationDescriptor({
    required this.id,
    required this.method,
    required this.path,
    this.serverOnly = false,
  });

  final String id;
  final AuthOperationMethod method;
  final String path;
  final bool serverOnly;
}

final class AuthPersistenceSchema {
  const AuthPersistenceSchema({
    required this.id,
    required this.entities,
    this.atomicOperations = const <AuthAtomicOperationDescriptor>[],
  });

  final String id;
  final List<AuthEntityDescriptor> entities;
  final List<AuthAtomicOperationDescriptor> atomicOperations;
}

final class AuthEntityDescriptor {
  const AuthEntityDescriptor({
    required this.id,
    required this.fields,
    this.relationships = const <AuthRelationshipDescriptor>[],
    this.uniqueConstraints = const <List<String>>[],
    this.indexes = const <List<String>>[],
  });

  final String id;
  final List<AuthFieldDescriptor> fields;
  final List<AuthRelationshipDescriptor> relationships;
  final List<List<String>> uniqueConstraints;
  final List<List<String>> indexes;
}

final class AuthFieldDescriptor {
  const AuthFieldDescriptor({required this.name, required this.kind});

  final String name;
  final String kind;
}

final class AuthRelationshipDescriptor {
  const AuthRelationshipDescriptor({
    required this.field,
    required this.targetEntity,
    this.cascadeDelete = false,
  });

  final String field;
  final String targetEntity;
  final bool cascadeDelete;
}

final class AuthAtomicOperationDescriptor {
  const AuthAtomicOperationDescriptor({
    required this.id,
    required this.description,
  });

  final String id;
  final String description;
}

class AuthServerPluginContext<TContext> {
  const AuthServerPluginContext({
    required this.store,
    this.passwordHasher,
    this.passwordPolicy = const PasswordPolicy(),
    this.sessionStrategy = AuthSessionStrategy.session,
  });

  final AuthStore store;
  final PasswordHasher? passwordHasher;
  final PasswordPolicy passwordPolicy;
  final AuthSessionStrategy sessionStrategy;
}

abstract interface class AuthServerPlugin<TContext> {
  String get id;

  void configure(AuthServerPluginContext<TContext> context);
}

class AuthServerPluginRegistry<TContext> {
  AuthServerPluginRegistry({
    required AuthStore store,
    PasswordHasher? passwordHasher,
    PasswordPolicy passwordPolicy = const PasswordPolicy(),
    AuthSessionStrategy sessionStrategy = AuthSessionStrategy.session,
  }) : _store = store,
       _passwordHasher = passwordHasher ?? Argon2idPasswordHasher(),
       _passwordPolicy = passwordPolicy,
       _sessionStrategy = sessionStrategy;

  final AuthStore _store;
  final PasswordHasher _passwordHasher;
  final PasswordPolicy _passwordPolicy;
  final AuthSessionStrategy _sessionStrategy;
  final Map<String, AuthServerPlugin<TContext>> _plugins =
      <String, AuthServerPlugin<TContext>>{};
  final Map<String, AuthEndpointDescriptor<TContext>> _endpoints =
      <String, AuthEndpointDescriptor<TContext>>{};
  final Map<String, AuthEndpointDescriptor<TContext>> _hostEndpoints =
      <String, AuthEndpointDescriptor<TContext>>{};
  final Map<String, String> _endpointPluginIds = <String, String>{};
  final Set<String> _endpointKeys = <String>{};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  void register(AuthServerPlugin<TContext> plugin) {
    if (_frozen) throw StateError('Auth plugin topology is frozen.');
    final id = plugin.id.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(plugin.id, 'plugin.id', 'must not be empty');
    }
    if (_plugins.containsKey(id)) {
      throw StateError('Auth plugin "$id" is already registered.');
    }

    _plugins[id] = plugin;
    plugin.configure(
      AuthServerPluginContext<TContext>(
        store: _store,
        passwordHasher: _passwordHasher,
        passwordPolicy: _passwordPolicy,
        sessionStrategy: _sessionStrategy,
      ),
    );
  }

  void freeze() {
    if (_frozen) return;
    final topology = List<AuthServerPlugin<TContext>>.unmodifiable(
      _plugins.values,
    );
    _bindDeletionTopology(topology);
    for (final plugin
        in topology.whereType<AuthServerPluginTopologyAware<TContext>>()) {
      plugin.composePluginTopology(topology);
    }
    for (final plugin in topology) {
      if (plugin case AuthEndpointContributor<TContext>(:final endpoints)) {
        _registerEndpoints(plugin.id, endpoints, _endpoints);
      }
      if (plugin case AuthHostEndpointContributor<TContext>(
        :final hostEndpoints,
      )) {
        _registerEndpoints(plugin.id, hostEndpoints, _hostEndpoints);
      }
    }
    _frozen = true;
  }

  void _bindDeletionTopology(List<AuthServerPlugin<TContext>> topology) {
    final deletionContributors = topology
        .whereType<AuthUserDeletionPlanContributor>()
        .toList(growable: false);
    final deletionHost = _store is AuthUserDeletionCoordinatorHost
        ? _store as AuthUserDeletionCoordinatorHost
        : null;
    if (deletionHost == null && deletionContributors.isNotEmpty) {
      throw StateError(
        'The auth store cannot coordinate plugin-owned user deletion plans.',
      );
    }
    deletionHost?.bindUserDeletionPlanContributors(deletionContributors);
  }

  AuthServerPlugin<TContext>? find(String id) => _plugins[id.trim()];

  bool contains(String id) => find(id) != null;

  Iterable<AuthServerPlugin<TContext>> get values =>
      List<AuthServerPlugin<TContext>>.unmodifiable(_plugins.values);

  Iterable<AuthEndpointDescriptor<TContext>> get endpoints =>
      List<AuthEndpointDescriptor<TContext>>.unmodifiable(_endpoints.values);

  /// Public endpoint contracts for runtime plugin routes and host-owned routes.
  ///
  /// Framework adapters mount only [endpoints]. Documentation and client
  /// generators use this complete view so host-owned opt-in routes remain
  /// coupled to the plugin that enables them.
  Iterable<AuthEndpointDescriptor<TContext>> get publicEndpoints =>
      List<AuthEndpointDescriptor<TContext>>.unmodifiable(
        <AuthEndpointDescriptor<TContext>>[
          ..._endpoints.values,
          ..._hostEndpoints.values,
        ],
      );

  /// Returns the plugin that contributed [endpointId], after [freeze].
  String? pluginIdForEndpoint(String endpointId) =>
      _endpointPluginIds[endpointId.trim()];

  void _registerEndpoints(
    String rawPluginId,
    Iterable<AuthEndpointDescriptor<TContext>> endpoints,
    Map<String, AuthEndpointDescriptor<TContext>> destination,
  ) {
    final pluginId = rawPluginId.trim();
    for (final endpoint in endpoints) {
      final endpointId = endpoint.id.trim();
      final path = _normalizeEndpointPath(endpoint.path);
      if (endpointId.isEmpty || path.isEmpty) {
        throw ArgumentError(
          'Plugin "$rawPluginId" contributed an invalid endpoint.',
        );
      }
      if (_endpointPluginIds.containsKey(endpointId)) {
        throw StateError('Auth endpoint "$endpointId" is already registered.');
      }
      final key = '${endpoint.method.name}:$path';
      if (!_endpointKeys.add(key)) {
        throw StateError('Auth endpoint path "$key" is already registered.');
      }
      destination[endpointId] = endpoint;
      _endpointPluginIds[endpointId] = pluginId;
    }
  }

  Future<void> enforceAuthenticationPolicy(
    AuthAuthenticationPolicyRequest<TContext> request,
  ) async {
    for (final plugin
        in _plugins.values
            .whereType<AuthAuthenticationPolicyContributor<TContext>>()) {
      await plugin.enforceAuthenticationPolicy(request);
    }
  }

  Future<void> emitAuthenticationLifecycleEvent(
    AuthAuthenticationLifecycleEvent<TContext> event,
  ) async {
    for (final plugin
        in _plugins.values
            .whereType<AuthAuthenticationLifecycleContributor<TContext>>()) {
      await plugin.onAuthenticationLifecycleEvent(event);
    }
  }

  Future<void> enforceCredentialPolicy(
    AuthCredentialPolicyRequest<TContext> request,
  ) async {
    for (final plugin
        in _plugins.values
            .whereType<AuthCredentialPolicyContributor<TContext>>()) {
      await plugin.enforceCredentialPolicy(request);
    }
  }

  Future<void> enforcePasswordPolicy(
    AuthPasswordPolicyRequest<TContext> request,
  ) async {
    for (final plugin
        in _plugins.values
            .whereType<AuthPasswordPolicyContributor<TContext>>()) {
      await plugin.enforcePasswordPolicy(request);
    }
  }

  Iterable<AuthPersistenceSchema> get persistenceSchemas =>
      List<AuthPersistenceSchema>.unmodifiable(
        _plugins.values.whereType<AuthPersistenceContributor>().expand(
          (plugin) => plugin.persistenceSchemas,
        ),
      );

  Iterable<AuthClientOperationDescriptor> get clientOperations =>
      List<AuthClientOperationDescriptor>.unmodifiable(
        _plugins.values
            .whereType<AuthClientOperationContributor>()
            .expand((plugin) => plugin.clientOperations)
            .where((operation) => !operation.serverOnly),
      );

  Iterable<AuthRateLimitOperation> get rateLimitOperations =>
      List<AuthRateLimitOperation>.unmodifiable(
        _plugins.values.whereType<AuthRateLimitContributor>().expand(
          (plugin) => plugin.rateLimitOperations,
        ),
      );
}

String _normalizeEndpointPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return '/${trimmed.replaceAll(RegExp(r'^/+|/+$'), '')}';
}
