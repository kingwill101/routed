import 'dart:async';

import 'package:server_auth/src/core/authentication_methods.dart';
import 'package:server_auth/src/core/deletion_transaction.dart';
import 'package:server_auth/src/core/models.dart';
import 'package:server_auth/src/core/password_hasher.dart';
import 'package:server_auth/src/core/password_policy.dart';
import 'package:server_auth/src/core/providers.dart';
import 'package:server_auth/src/core/rate_limit.dart';
import 'package:server_auth/src/core/store.dart';

/// HTTP method exposed by a portable auth plugin operation.
enum AuthOperationMethod {
  /// Reads state without changing it.
  get,

  /// Creates or otherwise submits a state-changing operation.
  post,

  /// Replaces a resource or operation state.
  put,

  /// Partially updates a resource or operation state.
  patch,

  /// Removes a resource or operation state.
  delete,
}

/// Where a portable auth endpoint is mounted by a framework host.
enum AuthEndpointMount {
  /// Mounts the route below the configured auth base path.
  auth,

  /// Mounts the route at the host application's root path.
  root,
}

/// A declared key for one dynamic auth route segment.
final class AuthRouteParameterKey {
  /// Creates a typed key for a route parameter named [name].
  const AuthRouteParameterKey(this.name);

  /// Name of the route parameter.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is AuthRouteParameterKey && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// A framework-neutral auth route using canonical `{parameter}` segments.
final class AuthRoutePath {
  /// Creates a route [template] with its declared placeholder parameters.
  const AuthRoutePath(
    this.template, {
    this.parameters = const <AuthRouteParameterKey>[],
  });

  /// Canonical route template, such as `/users/{userId}`.
  final String template;

  /// Typed keys corresponding exactly to placeholders in [template].
  final List<AuthRouteParameterKey> parameters;

  /// Validates this route and returns its canonical template.
  String validate() {
    final value = template.trim();
    if (value != template ||
        !value.startsWith('/') ||
        value.startsWith('//') ||
        (value.length > 1 && value.endsWith('/')) ||
        value.contains('?') ||
        value.contains('#')) {
      throw ArgumentError.value(
        template,
        'template',
        'must be a canonical absolute path without a query or fragment',
      );
    }

    final declared = <String>{};
    for (final parameter in parameters) {
      if (!_authRouteParameterPattern.hasMatch(parameter.name)) {
        throw ArgumentError.value(
          parameter.name,
          'parameters',
          'must be a valid route parameter name',
        );
      }
      if (!declared.add(parameter.name)) {
        throw ArgumentError.value(
          parameters,
          'parameters',
          'contains duplicate parameter "${parameter.name}"',
        );
      }
    }

    if (value == '/') {
      if (declared.isNotEmpty) {
        throw ArgumentError.value(
          parameters,
          'parameters',
          'must be empty for the root route',
        );
      }
      return value;
    }

    final placeholders = <String>{};
    for (final segment in value.split('/').skip(1)) {
      if (segment.isEmpty) {
        throw ArgumentError.value(
          template,
          'template',
          'must not contain empty path segments',
        );
      }
      final match = _authRoutePlaceholderPattern.firstMatch(segment);
      if (match != null && match.group(0) == segment) {
        final name = match.group(1)!;
        if (!placeholders.add(name)) {
          throw ArgumentError.value(
            template,
            'template',
            'contains duplicate placeholder "$name"',
          );
        }
      } else if (segment == '.' ||
          segment == '..' ||
          segment.contains('{') ||
          segment.contains('}') ||
          !_authRouteStaticSegmentPattern.hasMatch(segment)) {
        throw ArgumentError.value(
          template,
          'template',
          'contains an invalid path segment "$segment"',
        );
      }
    }

    final missing = placeholders.difference(declared);
    final extra = declared.difference(placeholders);
    if (missing.isNotEmpty || extra.isNotEmpty) {
      throw ArgumentError.value(
        parameters,
        'parameters',
        'must exactly declare route placeholders; missing: '
            '${missing.join(', ')}, extra: ${extra.join(', ')}',
      );
    }
    return value;
  }

  /// Route shape used to detect collisions independent of parameter names.
  String get collisionShape =>
      validate().replaceAll(_authRoutePlaceholderPattern, '{}');

  /// Resolves this route with an exact set of typed parameters.
  String resolve(Map<AuthRouteParameterKey, String> values) {
    final canonical = validate();
    final expected = parameters.toSet();
    final supplied = values.keys.toSet();
    final missing = expected.difference(supplied);
    final extra = supplied.difference(expected);
    if (missing.isNotEmpty || extra.isNotEmpty) {
      throw ArgumentError.value(
        values,
        'values',
        'must exactly match route parameters; missing: '
            '${missing.map((key) => key.name).join(', ')}, extra: '
            '${extra.map((key) => key.name).join(', ')}',
      );
    }
    return canonical.replaceAllMapped(_authRoutePlaceholderPattern, (match) {
      final key = parameters.singleWhere(
        (candidate) => candidate.name == match.group(1),
      );
      final value = values[key];
      if (value == null || value.isEmpty) {
        throw ArgumentError.value(value, key.name, 'must not be empty');
      }
      if (value == '.' || value == '..') {
        throw ArgumentError.value(
          value,
          key.name,
          'must not be a URI dot segment',
        );
      }
      return Uri.encodeComponent(value);
    });
  }

  /// Converts framework route parameters into their declared typed keys.
  Map<AuthRouteParameterKey, String> bind(Map<String, Object?> values) {
    validate();
    final byName = <String, AuthRouteParameterKey>{
      for (final parameter in parameters) parameter.name: parameter,
    };
    final supplied = values.keys.toSet();
    final expected = byName.keys.toSet();
    final missing = expected.difference(supplied);
    final extra = supplied.difference(expected);
    if (missing.isNotEmpty || extra.isNotEmpty) {
      throw ArgumentError.value(
        values,
        'values',
        'must exactly match route parameters; missing: ${missing.join(', ')}, '
            'extra: ${extra.join(', ')}',
      );
    }
    final bound = <AuthRouteParameterKey, String>{};
    for (final entry in values.entries) {
      final value = entry.value?.toString();
      if (value == null || value.isEmpty) {
        throw ArgumentError.value(value, entry.key, 'must not be empty');
      }
      bound[byName[entry.key]!] = value;
    }
    return Map<AuthRouteParameterKey, String>.unmodifiable(bound);
  }

  @override
  String toString() => template;
}

final RegExp _authRouteParameterPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');
final RegExp _authRoutePlaceholderPattern = RegExp(
  r'\{([A-Za-z][A-Za-z0-9_]*)\}',
);
final RegExp _authRouteStaticSegmentPattern = RegExp(r'^[A-Za-z0-9._~-]+$');

/// Typed key for the provider parameter used by built-in provider routes.
const AuthRouteParameterKey authProviderRouteParameter = AuthRouteParameterKey(
  'provider',
);

/// Route template for starting provider sign-in.
const AuthRoutePath authSignInProviderRoute = AuthRoutePath(
  '/signin/{provider}',
  parameters: <AuthRouteParameterKey>[authProviderRouteParameter],
);

/// Route template for starting provider registration.
const AuthRoutePath authRegisterProviderRoute = AuthRoutePath(
  '/register/{provider}',
  parameters: <AuthRouteParameterKey>[authProviderRouteParameter],
);

/// Route template for completing a provider callback.
const AuthRoutePath authCallbackProviderRoute = AuthRoutePath(
  '/callback/{provider}',
  parameters: <AuthRouteParameterKey>[authProviderRouteParameter],
);

/// Namespaced request data supplied to a portable auth endpoint.
final class AuthEndpointRequest {
  /// Creates an endpoint request with immutable path, query, body, and headers.
  AuthEndpointRequest({
    Map<AuthRouteParameterKey, String> path =
        const <AuthRouteParameterKey, String>{},
    Map<String, dynamic> query = const <String, dynamic>{},
    Map<String, dynamic> body = const <String, dynamic>{},
    Map<String, String> headers = const <String, String>{},
  }) : path = Map<AuthRouteParameterKey, String>.unmodifiable(path),
       query = Map<String, dynamic>.unmodifiable(query),
       body = Map<String, dynamic>.unmodifiable(body),
       headers = Map<String, String>.unmodifiable(
         headers.map((key, value) => MapEntry(key.toLowerCase(), value)),
       );

  /// Creates an empty endpoint request.
  const AuthEndpointRequest.empty()
    : path = const <AuthRouteParameterKey, String>{},
      query = const <String, dynamic>{},
      body = const <String, dynamic>{},
      headers = const <String, String>{};

  /// Values captured for declared route parameters.
  final Map<AuthRouteParameterKey, String> path;

  /// Query parameters supplied to the endpoint.
  final Map<String, dynamic> query;

  /// Decoded request body supplied to the endpoint.
  final Map<String, dynamic> body;

  /// Host-allowlisted headers exposed to portable handlers.
  ///
  /// Framework adapters are not required to forward arbitrary request
  /// headers. Routed currently forwards only `Authorization`.
  final Map<String, String> headers;

  /// Returns the path value for [key], or throws when it is absent or empty.
  String requirePath(AuthRouteParameterKey key) {
    final value = path[key];
    if (value == null || value.isEmpty) {
      throw FormatException('Missing route parameter "${key.name}".');
    }
    return value;
  }
}

/// Authentication boundary enforced for a portable auth plugin operation.
///
/// [bearer] identifies service-protocol endpoints whose plugin owns token
/// verification. The framework host forwards the Authorization header but
/// does not interpret or turn that credential into an application session.
enum AuthOperationAuthentication {
  /// Does not require an authenticated principal.
  none,

  /// Requires the host's normal authenticated session.
  session,

  /// Requires an API key supplied through the host transport.
  apiKey,

  /// Requires a bearer credential verified by the plugin.
  bearer,
}

/// Origin policy applied before a portable endpoint is invoked.
enum AuthOperationOriginPolicy {
  /// Does not require browser-origin validation.
  none,

  /// Applies the host's browser-origin validation policy.
  browser,
}

/// CSRF policy applied before a portable endpoint is invoked.
enum AuthOperationCsrfPolicy {
  /// Does not require a CSRF token.
  none,

  /// Requires the host's configured CSRF validation.
  required,
}

/// Whether an auth endpoint observes state or changes it.
///
/// Every endpoint descriptor must choose one of the two variants explicitly.
/// This keeps newly-added custom and host-owned endpoints from silently
/// bypassing persistence and replay-safety review.
sealed class AuthOperationSemantics {
  /// Creates endpoint semantics for a concrete read-only or mutation subtype.
  const AuthOperationSemantics();

  /// Creates read-only endpoint semantics.
  const factory AuthOperationSemantics.readOnly() =
      AuthReadOnlyOperationSemantics;

  /// Creates mutation semantics with persistence and replay guarantees.
  const factory AuthOperationSemantics.mutation({
    required AuthMutationPersistence persistence,
    required AuthMutationReplaySafety replaySafety,
  }) = AuthMutationOperationSemantics;
}

/// A state-observing endpoint.
final class AuthReadOnlyOperationSemantics extends AuthOperationSemantics {
  /// Creates read-only endpoint semantics.
  const AuthReadOnlyOperationSemantics();
}

/// The persistence boundary that owns a mutation.
enum AuthMutationPersistenceKind {
  /// Application or plugin state expected to survive process restarts.
  durable,

  /// Host session state, including issuing, rotating, or clearing a session.
  session,

  /// A short-lived challenge or browser-local value with a fixed lifetime.
  boundedEphemeral,

  /// State owned by an external application or identity provider.
  external,
}

/// Whether a mutation is committed as one indivisible persistence operation.
enum AuthMutationAtomicity {
  /// The mutation is committed as one indivisible operation.
  atomic,

  /// The mutation can expose intermediate persistence states.
  nonAtomic,

  /// Atomicity does not apply to this mutation.
  notApplicable,
}

/// What a caller can expect when the same mutation is submitted again.
enum AuthMutationReplaySafety {
  /// A committed result may be requested again without applying it twice.
  idempotent,

  /// The input can be consumed successfully at most once.
  singleUse,

  /// Repetition is an intentional part of the public operation.
  repeatable,

  /// The implementation does not currently provide a replay guarantee.
  unguarded,
}

/// A reference to public plugin persistence metadata.
///
/// [atomicOperationId] is required when an endpoint claims atomic durable
/// persistence. Conformance resolves both identifiers against the composed
/// [AuthPersistenceSchema] declarations.
final class AuthPersistenceOperationReference {
  /// Creates a reference to a persistence schema and optional atomic operation.
  const AuthPersistenceOperationReference({
    required this.schemaId,
    this.atomicOperationId,
  });

  /// Identifier of the persistence schema that owns the mutation.
  final String schemaId;

  /// Identifier of the atomic operation within [schemaId], when applicable.
  final String? atomicOperationId;
}

/// Typed persistence semantics for a state-changing auth operation.
final class AuthMutationPersistence {
  const AuthMutationPersistence._({
    required this.kind,
    required this.atomicity,
    this.reference,
  });

  /// Creates durable persistence semantics.
  const AuthMutationPersistence.durable({
    required AuthMutationAtomicity atomicity,
    AuthPersistenceOperationReference? reference,
  }) : this._(
         kind: AuthMutationPersistenceKind.durable,
         atomicity: atomicity,
         reference: reference,
       );

  /// Creates session-state persistence semantics.
  const AuthMutationPersistence.session()
    : this._(
        kind: AuthMutationPersistenceKind.session,
        atomicity: AuthMutationAtomicity.notApplicable,
      );

  /// Creates bounded-ephemeral persistence semantics.
  const AuthMutationPersistence.boundedEphemeral()
    : this._(
        kind: AuthMutationPersistenceKind.boundedEphemeral,
        atomicity: AuthMutationAtomicity.notApplicable,
      );

  /// Creates external-state persistence semantics.
  const AuthMutationPersistence.external()
    : this._(
        kind: AuthMutationPersistenceKind.external,
        atomicity: AuthMutationAtomicity.notApplicable,
      );

  /// Persistence boundary that owns the mutation.
  final AuthMutationPersistenceKind kind;

  /// Atomicity guarantee for durable persistence.
  final AuthMutationAtomicity atomicity;

  /// Schema and operation reference for durable persistence, when supplied.
  final AuthPersistenceOperationReference? reference;
}

/// A state-changing endpoint with explicit persistence and replay behavior.
final class AuthMutationOperationSemantics extends AuthOperationSemantics {
  /// Creates mutation semantics with explicit persistence and replay behavior.
  const AuthMutationOperationSemantics({
    required this.persistence,
    required this.replaySafety,
  });

  /// Persistence boundary and atomicity declaration.
  final AuthMutationPersistence persistence;

  /// Replay guarantee for repeated submissions.
  final AuthMutationReplaySafety replaySafety;
}

/// Serialization contract for one side of an auth operation.
///
/// [schema] is JSON Schema Draft 2020-12 metadata. It is optional at runtime,
/// but integrations such as OpenAPI can use it without depending on a
/// framework-specific route type.
abstract interface class AuthOperationContract {
  /// JSON Schema metadata for the encoded value.
  Map<String, Object?> get schema;

  /// Media type emitted or accepted by the codec.
  String get contentType;

  /// Whether the value is required by the contract.
  bool get required;
}

/// Encodes and decodes one side of a typed auth operation.
final class AuthOperationCodec<T> implements AuthOperationContract {
  /// Creates a codec from [decode] and [encode] callbacks.
  const AuthOperationCodec({
    required this.decode,
    required this.encode,
    this.schema = const <String, Object?>{},
    this.contentType = 'application/json',
    this.required = false,
  });

  /// Decodes a JSON object into [T].
  final T Function(Map<String, dynamic> json) decode;

  /// Encodes a [T] value into a JSON-compatible object.
  final Object? Function(T value) encode;

  /// JSON Schema metadata for the encoded value.
  @override
  final Map<String, Object?> schema;

  /// Media type emitted or accepted by the codec.
  @override
  final String contentType;

  /// Whether the value is required by the contract.
  @override
  final bool required;
}

/// Host context and authenticated state passed to a typed endpoint handler.
final class AuthOperationInvocation<TContext> {
  /// Creates the host context supplied to a portable endpoint handler.
  const AuthOperationInvocation({
    required this.context,
    required this.user,
    this.request = const AuthEndpointRequest.empty(),
    this.emailVerified = false,
    this.activeOrganizationId,
    this.activeTeamId,
    this.writeActiveSelection,
    this.sessionControl,
  });

  /// Framework context associated with the request.
  final TContext context;

  /// Authenticated user, or `null` for an anonymous invocation.
  final AuthUser? user;

  /// Namespaced request data supplied to the handler.
  final AuthEndpointRequest request;

  /// Whether the current principal has a verified email address.
  final bool emailVerified;

  /// Active organization selected for this session, when available.
  final String? activeOrganizationId;

  /// Active team selected for this session, when available.
  final String? activeTeamId;

  /// Callback for persisting a changed organization/team selection.
  final FutureOr<void> Function(String? organizationId, String? teamId)?
  writeActiveSelection;

  /// Host-owned session operations available to the handler.
  final AuthServerPluginSessionControl? sessionControl;

  /// Returns a copy carrying [request].
  AuthOperationInvocation<TContext> withRequest(AuthEndpointRequest request) =>
      AuthOperationInvocation<TContext>(
        context: context,
        user: user,
        request: request,
        emailVerified: emailVerified,
        activeOrganizationId: activeOrganizationId,
        activeTeamId: activeTeamId,
        writeActiveSelection: writeActiveSelection,
        sessionControl: sessionControl,
      );
}

/// A framework-neutral redirect returned by an auth plugin endpoint.
final class AuthEndpointRedirect {
  /// Creates a redirect response to [location].
  const AuthEndpointRedirect({
    required this.location,
    this.statusCode = 302,
    this.headers = const <String, String>{},
  });

  /// Destination URI for the redirect.
  final Uri location;

  /// HTTP status code used for the redirect.
  final int statusCode;

  /// Additional response headers.
  final Map<String, String> headers;
}

/// An explicit HTTP response returned by a portable plugin endpoint.
///
/// Most auth operations return JSON with status 200. Protocol plugins that
/// require another success status, response headers, or an empty body can use
/// this value without coupling themselves to a framework response class.
final class AuthEndpointHttpResponse {
  /// Creates an explicit HTTP response with a valid [statusCode].
  AuthEndpointHttpResponse({
    required this.statusCode,
    this.body,
    Map<String, String> headers = const <String, String>{},
  }) : headers = Map<String, String>.unmodifiable(headers) {
    if (statusCode < 100 || statusCode > 599) {
      throw ArgumentError.value(
        statusCode,
        'statusCode',
        'must be a valid HTTP status code',
      );
    }
  }

  /// HTTP status code returned to the client.
  final int statusCode;

  /// Response body, usually a JSON-compatible value.
  final Object? body;

  /// Response headers returned to the client.
  final Map<String, String> headers;
}

/// Host-owned session operations available to portable plugin endpoints.
abstract interface class AuthServerPluginSessionControl {
  /// Session strategy used by the host.
  AuthSessionStrategy get strategy;

  /// Current server-side session identifier, when available.
  String? get currentSessionId;

  /// Clears the current host-owned session.
  FutureOr<void> signOut();
}

/// Lifecycle phase emitted by the host after it completes an authentication
/// transition or clears one.
enum AuthAuthenticationLifecycleEventType {
  /// A user successfully authenticated.
  authenticationSucceeded,

  /// The current user signed out.
  signedOut,

  /// The current account was deleted.
  accountDeleted,
}

/// Typed, in-memory host lifecycle event for optional authentication plugins.
///
/// The event is intentionally not serializable. [authenticationMethod] is a
/// host-owned stable method label, never a credential, token, identifier, or
/// provider response. OAuth hosts may additionally provide the bounded
/// provider namespace in [oauthProviderNamespace].
final class AuthAuthenticationLifecycleEvent<TContext> {
  /// Creates a lifecycle event delivered to plugin contributors.
  const AuthAuthenticationLifecycleEvent({
    required this.type,
    required this.context,
    required this.strategy,
    this.authenticationMethod,
    this.oauthProviderNamespace,
  });

  /// Lifecycle transition represented by the event.
  final AuthAuthenticationLifecycleEventType type;

  /// Framework context associated with the transition.
  final TContext context;

  /// Session strategy used by the host.
  final AuthSessionStrategy strategy;

  /// Stable authentication-method label, when known.
  final String? authenticationMethod;

  /// Provider namespace associated with an OAuth transition, when known.
  final String? oauthProviderNamespace;
}

/// Optional plugin contributor notified only after host-owned lifecycle work
/// has completed.
abstract interface class AuthAuthenticationLifecycleContributor<TContext> {
  /// Handles a completed authentication lifecycle transition.
  FutureOr<void> onAuthenticationLifecycleEvent(
    AuthAuthenticationLifecycleEvent<TContext> event,
  );
}

/// Authentication boundary at which a policy is evaluated.
enum AuthAuthenticationPolicyPhase {
  /// Runs immediately before a session is issued.
  beforeSessionIssue,

  /// Runs while an existing session is resolved.
  resolveSession,
}

/// Context supplied to an authentication policy contributor.
final class AuthAuthenticationPolicyRequest<TContext> {
  /// Creates a request for an authentication policy contributor.
  const AuthAuthenticationPolicyRequest({
    required this.context,
    required this.user,
    required this.phase,
  });

  /// Framework context associated with the authentication attempt.
  final TContext context;

  /// User being authenticated.
  final AuthUser user;

  /// Policy phase being evaluated.
  final AuthAuthenticationPolicyPhase phase;
}

/// Optional plugin contribution consulted at every authentication boundary.
abstract interface class AuthAuthenticationPolicyContributor<TContext> {
  /// Enforces application policy for an authentication boundary.
  FutureOr<void> enforceAuthenticationPolicy(
    AuthAuthenticationPolicyRequest<TContext> request,
  );
}

/// Credential operation at which an application-owned credential policy runs.
enum AuthCredentialPolicyOperation {
  /// A user is attempting to sign in with credentials.
  signIn,

  /// A user is registering a new credential.
  registration,
}

/// Non-password input supplied to credential policy contributors.
///
/// [verificationToken] is delivery-only request data. It is deliberately not
/// serializable and must not be logged, persisted, or copied into a provider
/// response. The value is supplied only to the policy contributor that needs
/// it, before the credential provider is invoked.
final class AuthCredentialPolicyRequest<TContext> {
  /// Creates a request for a credential policy contributor.
  const AuthCredentialPolicyRequest({
    required this.context,
    required this.provider,
    required this.operation,
    this.identifier,
    this.verificationToken,
  });

  /// Framework context associated with the credential operation.
  final TContext context;

  /// Provider handling the credential operation.
  final AuthProvider provider;

  /// Credential operation being evaluated.
  final AuthCredentialPolicyOperation operation;

  /// Normalized credential identifier, when supplied.
  final String? identifier;

  /// Delivery-only verification token, when supplied.
  final String? verificationToken;
}

/// Optional policy consulted immediately before a credential provider runs.
abstract interface class AuthCredentialPolicyContributor<TContext> {
  /// Enforces application policy before credentials are accepted.
  FutureOr<void> enforceCredentialPolicy(
    AuthCredentialPolicyRequest<TContext> request,
  );
}

/// Password mutation protected by an application-owned password policy.
enum AuthPasswordPolicyOperation {
  /// A password supplied during registration.
  registration,

  /// A password supplied during password reset.
  passwordReset,

  /// A password supplied during password change.
  passwordChange,
}

/// Request passed to password policy contributors.
///
/// [password] is a secret and exists only for the duration of the policy
/// call. This type intentionally has no JSON or diagnostic representation.
final class AuthPasswordPolicyRequest<TContext> {
  /// Creates a request for a password policy contributor.
  const AuthPasswordPolicyRequest({
    required this.context,
    required this.operation,
    required this.password,
    this.user,
  });

  /// Framework context associated with the password operation.
  final TContext context;

  /// Password operation being evaluated.
  final AuthPasswordPolicyOperation operation;

  /// Plaintext password supplied only for the duration of the policy call.
  final String password;

  /// Existing user associated with the operation, when known.
  final AuthUser? user;
}

/// Optional policy consulted before a new password is accepted.
abstract interface class AuthPasswordPolicyContributor<TContext> {
  /// Enforces application policy before a password is accepted.
  FutureOr<void> enforcePasswordPolicy(
    AuthPasswordPolicyRequest<TContext> request,
  );
}

/// Plugin-owned credentials or tokens that must be revoked when a user is
/// made unavailable without deleting their data.
abstract interface class AuthUserAccessRevocationContributor {
  /// Namespace of credentials or tokens revoked by this contributor.
  String get userAccessNamespace;

  /// Revokes this contributor's access records for [userId].
  FutureOr<void> revokeUserAccess(String userId);
}

/// Optional second-pass composition after every plugin has been registered.
abstract interface class AuthServerPluginTopologyAware<TContext> {
  /// Composes this plugin with the complete registered plugin topology.
  void composePluginTopology(Iterable<AuthServerPlugin<TContext>> plugins);
}

/// Declares the persistent data and destructive routes owned by one server
/// plugin.
///
/// A plugin that contributes an authentication-method inventory must declare
/// the same namespace here. A plugin that contributes user-owned deletion
/// plans must declare its deletion namespace here. [removalEndpointIds]
/// identifies credential-removal or credential-rotation routes that require
/// the host's recent-authentication boundary; the registry verifies that each
/// route is contributed by this plugin and is an explicit mutation.
///
/// Plugins that own neither authentication methods nor user-owned data should
/// return [AuthServerPluginDataContract.none]. This declaration is required
/// on every [AuthServerPlugin], so external plugins cannot silently omit their
/// cleanup and account-safety topology.
final class AuthServerPluginDataContract {
  /// Creates a declaration of plugin-owned data and removal endpoints.
  const AuthServerPluginDataContract({
    this.authenticationMethodNamespace,
    this.userDataNamespace,
    this.removalEndpointIds = const <String>[],
  });

  /// Creates a declaration for a plugin that owns no user data or methods.
  const AuthServerPluginDataContract.none()
    : authenticationMethodNamespace = null,
      userDataNamespace = null,
      removalEndpointIds = const <String>[];

  /// Namespace declared by [AuthAuthenticationMethodInventoryContributor].
  final String? authenticationMethodNamespace;

  /// Namespace declared by [AuthUserDeletionPlanContributor].
  final String? userDataNamespace;

  /// Plugin endpoint IDs that remove or rotate an owned login credential.
  final List<String> removalEndpointIds;
}

/// Handles one OAuth token grant for a host-owned token endpoint.
typedef AuthOAuthTokenGrantHandler<TContext> =
    FutureOr<Object?> Function(
      AuthOperationInvocation<TContext> invocation,
      Map<String, dynamic> request,
    );

/// Host for grant handlers sharing a single OAuth token endpoint.
abstract interface class AuthOAuthTokenEndpointHost<TContext> {
  /// Registers a handler for [grantType].
  void registerOAuthTokenGrant(
    String grantType,
    AuthOAuthTokenGrantHandler<TContext> handler,
  );
}

/// Describes and invokes one framework-neutral auth endpoint.
abstract interface class AuthEndpointDescriptor<TContext> {
  /// Stable endpoint identifier.
  String get id;

  /// HTTP method used by the endpoint.
  AuthOperationMethod get method;

  /// Canonical route path used by the endpoint.
  AuthRoutePath get path;

  /// Mount location selected by the endpoint.
  AuthEndpointMount get mount;

  /// Persistence and replay semantics declared by the endpoint.
  AuthOperationSemantics get semantics;

  /// Authentication boundary required by the endpoint.
  AuthOperationAuthentication get authentication;

  /// Browser-origin policy required by the endpoint.
  AuthOperationOriginPolicy get originPolicy;

  /// CSRF policy required by the endpoint.
  AuthOperationCsrfPolicy get csrfPolicy;

  /// Rate-limit operation applied by the host, when configured.
  AuthRateLimitOperation? get rateLimitOperation;

  /// Whether the endpoint is available only to server-side callers.
  bool get serverOnly;

  /// Invokes the endpoint with [invocation] and [request].
  FutureOr<Object?> invoke(
    AuthOperationInvocation<TContext> invocation,
    AuthEndpointRequest request,
  );
}

/// Optional security metadata for endpoints that remove or rotate a login
/// method.
///
/// Framework adapters must require recent original authentication or an
/// explicit step-up proof before invoking an endpoint that opts into this
/// contract. Keeping the requirement as endpoint metadata lets portable
/// plugins declare the boundary without depending on a session or router
/// implementation.
abstract interface class AuthEndpointSecurityDescriptor {
  /// Whether the host must require recent original authentication.
  bool get requiresRecentAuthentication;
}

/// Optional endpoint contribution used to derive a private rate-limit key.
///
/// The returned value is supplied only to [AuthRateLimiter]. Implementations
/// must return a canonical non-secret identifier and must never return a
/// password, captcha token, bearer credential, or other request secret.
abstract interface class AuthEndpointRateLimitIdentifierDescriptor {
  /// Decodes [request], derives an endpoint-specific key, and applies the common
  /// limiter-identifier safety boundary.
  ///
  /// Invalid endpoint input produces no identifier. The endpoint invocation
  /// still performs normal request decoding and returns its normal public
  /// validation error.
  String? resolveRateLimitIdentifier(AuthEndpointRequest request);
}

/// Derives a private limiter key from a successfully decoded endpoint request.
typedef AuthEndpointRateLimitIdentifierResolver<TRequest> =
    String? Function(TRequest request);

/// Projects a resolved session payload into an endpoint-specific response.
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
  /// Creates a host-owned authentication transition intent.
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

  /// User verified by the plugin.
  final AuthUser user;

  /// Stable label for the authentication method used.
  final String authenticationMethod;

  /// Provider that verified the user, when applicable.
  final AuthProvider? provider;

  /// Maximum age requested for the resulting authentication.
  final Duration? maximumAge;

  /// Administrator responsible for an impersonated session, when applicable.
  final String? impersonatedBy;

  /// Non-reserved metadata merged into the host session response.
  final Map<String, dynamic> metadata;
  final AuthEndpointAuthenticationProjector? _projectResponse;

  /// Projects the host-owned [sessionPayload] into a public response.
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
  /// Codec for decoding the endpoint request.
  AuthOperationContract get requestCodec;

  /// Codec for encoding the endpoint response.
  AuthOperationContract get responseCodec;
}

/// One explicit HTTP response advertised by a portable plugin operation.
///
/// Protocol plugins use this to publish non-200 success responses, empty
/// responses, and protocol-specific error media types without coupling their
/// implementation to an OpenAPI package.
final class AuthEndpointResponseContract {
  /// Creates a documented successful response contract.
  const AuthEndpointResponseContract({
    required this.statusCode,
    required this.description,
    this.contract,
  }) : assert(
         statusCode >= 100 && statusCode <= 599,
         'statusCode must be between 100 and 599',
       );

  /// HTTP status code represented by the response.
  final int statusCode;

  /// Human-readable response description.
  final String description;

  /// Optional body contract for the response.
  final AuthOperationContract? contract;
}

/// Optional complete HTTP response contract for an endpoint.
abstract interface class AuthEndpointResponseContractDescriptor {
  /// Response contracts advertised by the endpoint.
  Iterable<AuthEndpointResponseContract> get responseContracts;
}

/// Host-level failure that happened outside a plugin handler.
enum AuthEndpointPublicErrorKind {
  /// The request could not be decoded or validated.
  invalidRequest,

  /// The host failed while handling an otherwise valid request.
  internalFailure,
}

/// Creates a public HTTP response for a host-owned endpoint error.
typedef AuthEndpointPublicErrorResponseFactory =
    AuthEndpointHttpResponse Function(AuthEndpointPublicErrorKind kind);

/// Optional protocol-specific public errors for failures owned by the host.
abstract interface class AuthEndpointPublicErrorResponseDescriptor {
  /// Creates a public response for [kind], when the endpoint supports it.
  AuthEndpointHttpResponse? createPublicErrorResponse(
    AuthEndpointPublicErrorKind kind,
  );
}

/// Typed endpoint descriptor that owns request decoding and response encoding.
final class TypedAuthEndpointDescriptor<TContext, TRequest, TResponse>
    implements
        AuthEndpointDescriptor<TContext>,
        AuthEndpointSecurityDescriptor,
        AuthEndpointContractDescriptor,
        AuthEndpointResponseContractDescriptor,
        AuthEndpointPublicErrorResponseDescriptor,
        AuthEndpointRateLimitIdentifierDescriptor {
  /// Creates a typed endpoint descriptor.
  const TypedAuthEndpointDescriptor({
    required this.id,
    required this.method,
    required this.path,
    required this.requestCodec,
    required this.responseCodec,
    required this.handler,
    required this.semantics,
    this.authentication = AuthOperationAuthentication.session,
    this.originPolicy = AuthOperationOriginPolicy.browser,
    this.csrfPolicy = AuthOperationCsrfPolicy.none,
    this.rateLimitOperation,
    this.rateLimitIdentifier,
    this.requiresRecentAuthentication = false,
    this.responseContracts = const <AuthEndpointResponseContract>[],
    this.publicErrorResponse,
    this.serverOnly = false,
    this.mount = AuthEndpointMount.auth,
  });

  /// Stable endpoint identifier.
  @override
  final String id;

  /// HTTP method used by the endpoint.
  @override
  final AuthOperationMethod method;

  /// Canonical route path used by the endpoint.
  @override
  final AuthRoutePath path;

  /// Mount location selected by the endpoint.
  @override
  final AuthEndpointMount mount;

  /// Persistence and replay semantics declared by the endpoint.
  @override
  final AuthOperationSemantics semantics;

  /// Request codec used before [handler] runs.
  @override
  final AuthOperationCodec<TRequest> requestCodec;

  /// Response codec used after [handler] completes.
  @override
  final AuthOperationCodec<TResponse> responseCodec;

  /// Handler invoked with the decoded request.
  final FutureOr<TResponse> Function(
    AuthOperationInvocation<TContext> invocation,
    TRequest request,
  )
  handler;

  /// Authentication boundary required by the endpoint.
  @override
  final AuthOperationAuthentication authentication;

  /// Browser-origin policy required by the endpoint.
  @override
  final AuthOperationOriginPolicy originPolicy;

  /// CSRF policy required by the endpoint.
  @override
  final AuthOperationCsrfPolicy csrfPolicy;

  /// Rate-limit operation applied by the host, when configured.
  @override
  final AuthRateLimitOperation? rateLimitOperation;

  /// Resolves a private rate-limit identifier from a decoded request.
  final AuthEndpointRateLimitIdentifierResolver<TRequest>? rateLimitIdentifier;

  /// Whether recent original authentication is required.
  @override
  final bool requiresRecentAuthentication;

  /// Explicit success responses advertised by the endpoint.
  @override
  final Iterable<AuthEndpointResponseContract> responseContracts;

  /// Optional factory for protocol-specific public errors.
  final AuthEndpointPublicErrorResponseFactory? publicErrorResponse;

  /// Whether the endpoint is available only to server-side callers.
  @override
  final bool serverOnly;

  /// Creates the endpoint's public error response for [kind].
  @override
  AuthEndpointHttpResponse? createPublicErrorResponse(
    AuthEndpointPublicErrorKind kind,
  ) => publicErrorResponse?.call(kind);

  /// Resolves a private limiter identifier from [request].
  @override
  String? resolveRateLimitIdentifier(AuthEndpointRequest request) {
    final resolver = rateLimitIdentifier;
    if (resolver == null) return null;
    try {
      return normalizeAuthRateLimitIdentifier(
        resolver(requestCodec.decode(_requestPayload(request))),
      );
    } catch (_) {
      return null;
    }
  }

  /// Decodes, invokes, and encodes one endpoint request.
  @override
  Future<Object?> invoke(
    AuthOperationInvocation<TContext> invocation,
    AuthEndpointRequest request,
  ) async {
    final response = await handler(
      invocation.withRequest(request),
      requestCodec.decode(_requestPayload(request)),
    );
    return responseCodec.encode(response);
  }

  Map<String, dynamic> _requestPayload(AuthEndpointRequest request) =>
      switch (method) {
        AuthOperationMethod.get || AuthOperationMethod.delete => request.query,
        AuthOperationMethod.post ||
        AuthOperationMethod.put ||
        AuthOperationMethod.patch => request.body,
      };
}

/// Contributes runtime routes owned by a server plugin.
abstract interface class AuthEndpointContributor<TContext> {
  /// Runtime endpoints contributed by the plugin.
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints;
}

/// Public endpoint contracts implemented by the framework host.
///
/// These descriptors are included in documentation and generated clients but
/// are deliberately kept out of [AuthEndpointContributor.endpoints], because
/// the host owns their transport behavior and must not mount them through the
/// generic plugin invocation path.
abstract interface class AuthHostEndpointContributor<TContext> {
  /// Host-owned endpoint contracts enabled by the plugin.
  Iterable<AuthEndpointDescriptor<TContext>> get hostEndpoints;
}

/// Contributes persistence schemas owned by a server plugin.
abstract interface class AuthPersistenceContributor {
  /// Persistence schemas declared by the plugin.
  Iterable<AuthPersistenceSchema> get persistenceSchemas;
}

/// Contributes client operations owned by a server plugin.
abstract interface class AuthClientOperationContributor {
  /// Client operations declared by the plugin.
  Iterable<AuthClientOperationDescriptor> get clientOperations;
}

/// Contributes rate-limit operation metadata owned by a server plugin.
abstract interface class AuthRateLimitContributor {
  /// Rate-limit operations declared by the plugin.
  Iterable<AuthRateLimitOperation> get rateLimitOperations;
}

/// Describes one client-visible operation exposed by an auth plugin.
final class AuthClientOperationDescriptor {
  /// Creates a client operation descriptor.
  const AuthClientOperationDescriptor({
    required this.id,
    required this.method,
    required this.path,
    this.serverOnly = false,
    this.mount = AuthEndpointMount.auth,
  });

  /// Stable operation identifier.
  final String id;

  /// HTTP method used by the operation.
  final AuthOperationMethod method;

  /// Canonical route path used by the operation.
  final AuthRoutePath path;

  /// Whether the operation is intended only for server-side callers.
  final bool serverOnly;

  /// Mount location selected by the operation.
  final AuthEndpointMount mount;
}

/// Describes the persistence topology owned by an auth plugin.
final class AuthPersistenceSchema {
  /// Creates a persistence schema descriptor.
  const AuthPersistenceSchema({
    required this.id,
    required this.entities,
    this.atomicOperations = const <AuthAtomicOperationDescriptor>[],
  });

  /// Stable schema identifier.
  final String id;

  /// Entities stored by this schema.
  final List<AuthEntityDescriptor> entities;

  /// Atomic operations supported by this schema.
  final List<AuthAtomicOperationDescriptor> atomicOperations;
}

/// Describes one persisted entity in an auth plugin schema.
final class AuthEntityDescriptor {
  /// Creates an entity descriptor.
  const AuthEntityDescriptor({
    required this.id,
    required this.fields,
    this.relationships = const <AuthRelationshipDescriptor>[],
    this.uniqueConstraints = const <List<String>>[],
    this.indexes = const <List<String>>[],
  });

  /// Stable entity identifier.
  final String id;

  /// Fields persisted for the entity.
  final List<AuthFieldDescriptor> fields;

  /// Relationships to other entities.
  final List<AuthRelationshipDescriptor> relationships;

  /// Sets of fields that must be unique.
  final List<List<String>> uniqueConstraints;

  /// Field sets indexed for lookup.
  final List<List<String>> indexes;
}

/// Describes one persisted field in an auth plugin schema.
final class AuthFieldDescriptor {
  /// Creates a field descriptor with its name and storage kind.
  const AuthFieldDescriptor({required this.name, required this.kind});

  /// Field name.
  final String name;

  /// Storage or schema kind for the field.
  final String kind;
}

/// Describes a relationship between two persisted plugin entities.
final class AuthRelationshipDescriptor {
  /// Creates a relationship descriptor.
  const AuthRelationshipDescriptor({
    required this.field,
    required this.targetEntity,
    this.cascadeDelete = false,
  });

  /// Source field containing the relationship.
  final String field;

  /// Target entity identifier.
  final String targetEntity;

  /// Whether deleting the source cascades to the target.
  final bool cascadeDelete;
}

/// Describes one atomic persistence operation in a plugin schema.
final class AuthAtomicOperationDescriptor {
  /// Creates an atomic operation descriptor.
  const AuthAtomicOperationDescriptor({
    required this.id,
    required this.description,
  });

  /// Stable operation identifier.
  final String id;

  /// Human-readable operation description.
  final String description;
}

/// Context supplied while configuring a server plugin.
class AuthServerPluginContext<TContext> {
  /// Creates plugin configuration context from the host's stores and policies.
  const AuthServerPluginContext({
    required this.store,
    this.authenticationMethods,
    this.passwordHasher,
    this.passwordPolicy = const PasswordPolicy(),
    this.sessionStrategy = AuthSessionStrategy.session,
  });

  /// Typed persistence boundary shared by the runtime.
  final AuthStore store;

  /// Authentication-method service shared by the runtime, when available.
  final AuthAuthenticationMethodService? authenticationMethods;

  /// Password hasher selected by the host, when available.
  final PasswordHasher? passwordHasher;

  /// Password policy selected by the host.
  final PasswordPolicy passwordPolicy;

  /// Session strategy selected by the host.
  final AuthSessionStrategy sessionStrategy;
}

/// Contract implemented by every server plugin.
abstract interface class AuthServerPlugin<TContext> {
  /// Stable plugin identifier.
  String get id;

  /// Declares data and destructive routes owned by this plugin.
  AuthServerPluginDataContract get dataContract;

  /// Configures this plugin against the shared runtime context.
  void configure(AuthServerPluginContext<TContext> context);
}

/// Optional plugin check executed whenever auth boots in production posture.
abstract interface class AuthProductionPostureContributor {
  /// Validates that this plugin is safe for production boot.
  void validateProductionPosture();
}

/// Registry that composes, freezes, and exposes server plugin topology.
class AuthServerPluginRegistry<TContext> {
  /// Creates a registry for [store] and the shared authentication services.
  AuthServerPluginRegistry({
    required AuthStore store,
    required AuthAuthenticationMethodService authenticationMethods,
    PasswordHasher? passwordHasher,
    PasswordPolicy passwordPolicy = const PasswordPolicy(),
    AuthSessionStrategy sessionStrategy = AuthSessionStrategy.session,
    Iterable<String> historicalUserDataNamespaces = const [],
  }) : _store = store,
       _authenticationMethods = authenticationMethods,
       _passwordHasher = passwordHasher ?? Argon2idPasswordHasher(),
       _passwordPolicy = passwordPolicy,
       _sessionStrategy = sessionStrategy,
       _historicalUserDataNamespaces = _normalizeHistoricalUserDataNamespaces(
         historicalUserDataNamespaces,
       );

  final AuthStore _store;
  final AuthAuthenticationMethodService _authenticationMethods;
  final PasswordHasher _passwordHasher;
  final PasswordPolicy _passwordPolicy;
  final AuthSessionStrategy _sessionStrategy;
  final Set<String> _historicalUserDataNamespaces;
  final Map<String, AuthServerPlugin<TContext>> _plugins =
      <String, AuthServerPlugin<TContext>>{};
  final Map<String, AuthEndpointDescriptor<TContext>> _endpoints =
      <String, AuthEndpointDescriptor<TContext>>{};
  final Map<String, AuthEndpointDescriptor<TContext>> _hostEndpoints =
      <String, AuthEndpointDescriptor<TContext>>{};
  final Map<String, String> _endpointPluginIds = <String, String>{};
  final Set<String> _endpointKeys = <String>{};
  bool _frozen = false;

  /// Whether registration and topology mutation have been frozen.
  bool get isFrozen => _frozen;

  /// Registers and configures [plugin].
  ///
  /// Throws a [StateError] when the registry is frozen or the identifier is a
  /// duplicate.
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
        authenticationMethods: _authenticationMethods,
        passwordHasher: _passwordHasher,
        passwordPolicy: _passwordPolicy,
        sessionStrategy: _sessionStrategy,
      ),
    );
  }

  /// Finalizes plugin composition and validates the complete topology.
  void freeze() {
    if (_frozen) return;
    final topology = List<AuthServerPlugin<TContext>>.unmodifiable(
      _plugins.values,
    );
    _bindDeletionTopology(topology);
    _authenticationMethods.composeContributors(
      topology.whereType<AuthAuthenticationMethodInventoryContributor>(),
    );
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
    _validatePluginDataContracts(topology);
    _frozen = true;
  }

  void _validatePluginDataContracts(List<AuthServerPlugin<TContext>> topology) {
    for (final plugin in topology) {
      final contract = plugin.dataContract;
      final methodNamespace = _normalizeDataContractNamespace(
        contract.authenticationMethodNamespace,
        plugin: plugin,
        field: 'authenticationMethodNamespace',
      );
      final userNamespace = _normalizeDataContractNamespace(
        contract.userDataNamespace,
        plugin: plugin,
        field: 'userDataNamespace',
      );
      final inventory = plugin is AuthAuthenticationMethodInventoryContributor
          ? plugin as AuthAuthenticationMethodInventoryContributor
          : null;
      final inventoryEnabled =
          !(inventory == null) &&
          (plugin is! AuthAuthenticationMethodInventoryControl ||
              (plugin as AuthAuthenticationMethodInventoryControl)
                  .authenticationMethodInventoryEnabled);
      if (inventoryEnabled != (methodNamespace != null)) {
        throw StateError(
          'Plugin "${plugin.id}" must declare exactly one active '
          'authentication-method namespace in dataContract.',
        );
      }
      if (methodNamespace != null &&
          (inventory == null ||
              inventory.authenticationMethodNamespace != methodNamespace)) {
        throw StateError(
          'Plugin "${plugin.id}" dataContract authentication-method '
          'namespace does not match its typed inventory contributor.',
        );
      }

      final deletion = plugin is AuthUserDeletionPlanContributor
          ? plugin as AuthUserDeletionPlanContributor
          : null;
      if ((deletion != null) != (userNamespace != null)) {
        throw StateError(
          'Plugin "${plugin.id}" must declare its user-data namespace '
          'when it contributes user-deletion plans.',
        );
      }
      if (userNamespace != null &&
          (deletion == null || deletion.userDataNamespace != userNamespace)) {
        throw StateError(
          'Plugin "${plugin.id}" dataContract user-data namespace does '
          'not match its typed deletion contributor.',
        );
      }

      final endpointIds = <String>{};
      for (final rawEndpointId in contract.removalEndpointIds) {
        final endpointId = rawEndpointId.trim();
        if (endpointId.isEmpty || endpointId != rawEndpointId) {
          throw StateError(
            'Plugin "${plugin.id}" dataContract removal endpoint IDs '
            'must be non-empty and trimmed.',
          );
        }
        if (!endpointIds.add(endpointId)) {
          throw StateError(
            'Plugin "${plugin.id}" dataContract removal endpoint IDs '
            'must be unique.',
          );
        }
        final endpoint = _endpoints[endpointId] ?? _hostEndpoints[endpointId];
        if (endpoint == null || _endpointPluginIds[endpointId] != plugin.id) {
          throw StateError(
            'Plugin "${plugin.id}" dataContract references an endpoint '
            'it does not contribute: "$endpointId".',
          );
        }
        if (endpoint.semantics is! AuthMutationOperationSemantics ||
            endpoint is! AuthEndpointSecurityDescriptor ||
            !(endpoint as AuthEndpointSecurityDescriptor)
                .requiresRecentAuthentication) {
          throw StateError(
            'Plugin "${plugin.id}" removal endpoint "$endpointId" must '
            'declare a mutation and recent authentication.',
          );
        }
      }
    }
  }

  void _bindDeletionTopology(List<AuthServerPlugin<TContext>> topology) {
    final deletionContributors = topology
        .whereType<AuthUserDeletionPlanContributor>()
        .toList(growable: false);
    final deletionHost = _store is AuthUserDeletionCoordinatorHost
        ? _store as AuthUserDeletionCoordinatorHost
        : null;
    if (deletionHost == null &&
        (deletionContributors.isNotEmpty ||
            _historicalUserDataNamespaces.isNotEmpty)) {
      throw StateError(
        'The auth store cannot coordinate plugin-owned user deletion plans.',
      );
    }
    deletionHost?.bindUserDeletionPlanContributors(deletionContributors);
    if (_historicalUserDataNamespaces.isEmpty) return;
    final coordinator = deletionHost!.userDeletionCoordinator;
    if (coordinator
        case final AuthHistoricalUserDeletionNamespaceCoordinator capability) {
      capability.bindHistoricalUserDeletionNamespaces(
        _historicalUserDataNamespaces,
      );
    } else {
      throw StateError(
        'The auth store cannot guard historical user-data namespaces.',
      );
    }
  }

  /// Returns the registered plugin with [id], or `null` when absent.
  AuthServerPlugin<TContext>? find(String id) => _plugins[id.trim()];

  /// Returns whether a plugin with [id] is registered.
  bool contains(String id) => find(id) != null;

  /// Returns the registered plugins in registration order.
  Iterable<AuthServerPlugin<TContext>> get values =>
      List<AuthServerPlugin<TContext>>.unmodifiable(_plugins.values);

  /// Returns runtime endpoints contributed by registered plugins.
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
      endpoint.path.validate();
      if (endpointId.isEmpty) {
        throw ArgumentError(
          'Plugin "$rawPluginId" contributed an invalid endpoint.',
        );
      }
      if (_endpointPluginIds.containsKey(endpointId)) {
        throw StateError('Auth endpoint "$endpointId" is already registered.');
      }
      final key =
          '${endpoint.mount.name}:${endpoint.method.name}:'
          '${endpoint.path.collisionShape}';
      if (!_endpointKeys.add(key)) {
        throw StateError('Auth endpoint route "$key" is already registered.');
      }
      destination[endpointId] = endpoint;
      _endpointPluginIds[endpointId] = pluginId;
    }
  }

  /// Enforces authentication policies contributed by registered plugins.
  Future<void> enforceAuthenticationPolicy(
    AuthAuthenticationPolicyRequest<TContext> request,
  ) async {
    for (final plugin
        in _plugins.values
            .whereType<AuthAuthenticationPolicyContributor<TContext>>()) {
      await plugin.enforceAuthenticationPolicy(request);
    }
  }

  /// Emits a completed lifecycle event to registered contributors.
  Future<void> emitAuthenticationLifecycleEvent(
    AuthAuthenticationLifecycleEvent<TContext> event,
  ) async {
    for (final plugin
        in _plugins.values
            .whereType<AuthAuthenticationLifecycleContributor<TContext>>()) {
      await plugin.onAuthenticationLifecycleEvent(event);
    }
  }

  /// Enforces credential policies contributed by registered plugins.
  Future<void> enforceCredentialPolicy(
    AuthCredentialPolicyRequest<TContext> request,
  ) async {
    for (final plugin
        in _plugins.values
            .whereType<AuthCredentialPolicyContributor<TContext>>()) {
      await plugin.enforceCredentialPolicy(request);
    }
  }

  /// Enforces password policies contributed by registered plugins.
  Future<void> enforcePasswordPolicy(
    AuthPasswordPolicyRequest<TContext> request,
  ) async {
    for (final plugin
        in _plugins.values
            .whereType<AuthPasswordPolicyContributor<TContext>>()) {
      await plugin.enforcePasswordPolicy(request);
    }
  }

  /// Returns persistence schemas contributed by registered plugins.
  Iterable<AuthPersistenceSchema> get persistenceSchemas =>
      List<AuthPersistenceSchema>.unmodifiable(
        _plugins.values.whereType<AuthPersistenceContributor>().expand(
          (plugin) => plugin.persistenceSchemas,
        ),
      );

  /// Returns client-visible operations contributed by registered plugins.
  Iterable<AuthClientOperationDescriptor> get clientOperations =>
      List<AuthClientOperationDescriptor>.unmodifiable(
        _plugins.values
            .whereType<AuthClientOperationContributor>()
            .expand((plugin) => plugin.clientOperations)
            .where((operation) => !operation.serverOnly),
      );

  /// Returns rate-limit operations contributed by registered plugins.
  Iterable<AuthRateLimitOperation> get rateLimitOperations =>
      List<AuthRateLimitOperation>.unmodifiable(
        _plugins.values.whereType<AuthRateLimitContributor>().expand(
          (plugin) => plugin.rateLimitOperations,
        ),
      );
}

Set<String> _normalizeHistoricalUserDataNamespaces(Iterable<String> values) {
  final namespaces = <String>{};
  for (final value in values) {
    final normalized = value.trim().toLowerCase();
    if (normalized != value ||
        normalized.isEmpty ||
        normalized.length > 64 ||
        normalized.contains(RegExp(r'[\u0000-\u001f\u007f]')) ||
        !namespaces.add(normalized)) {
      throw ArgumentError.value(
        values,
        'historicalUserDataNamespaces',
        'must contain unique, bounded, canonical namespace values',
      );
    }
  }
  return Set<String>.unmodifiable(namespaces);
}

String? _normalizeDataContractNamespace<TContext>(
  String? value, {
  required AuthServerPlugin<TContext> plugin,
  required String field,
}) {
  if (value == null) return null;
  final normalized = value.trim();
  if (normalized != value ||
      normalized.isEmpty ||
      normalized.length > 64 ||
      normalized.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    throw StateError(
      'Plugin "${plugin.id}" dataContract $field must be a bounded, '
      'trimmed namespace.',
    );
  }
  return normalized;
}
