import 'dart:async';

import 'authentication_methods.dart';
import 'deletion_transaction.dart';
import 'models.dart';
import 'password_hasher.dart';
import 'password_policy.dart';
import 'providers.dart';
import 'rate_limit.dart';
import 'store.dart';

/// HTTP method exposed by a portable auth plugin operation.
enum AuthOperationMethod { get, post, put, patch, delete }

/// Where a portable auth endpoint is mounted by a framework host.
enum AuthEndpointMount { auth, root }

/// A declared key for one dynamic auth route segment.
final class AuthRouteParameterKey {
  const AuthRouteParameterKey(this.name);

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
  const AuthRoutePath(
    this.template, {
    this.parameters = const <AuthRouteParameterKey>[],
  });

  final String template;
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

const AuthRouteParameterKey authProviderRouteParameter = AuthRouteParameterKey(
  'provider',
);
const AuthRoutePath authSignInProviderRoute = AuthRoutePath(
  '/signin/{provider}',
  parameters: <AuthRouteParameterKey>[authProviderRouteParameter],
);
const AuthRoutePath authRegisterProviderRoute = AuthRoutePath(
  '/register/{provider}',
  parameters: <AuthRouteParameterKey>[authProviderRouteParameter],
);
const AuthRoutePath authCallbackProviderRoute = AuthRoutePath(
  '/callback/{provider}',
  parameters: <AuthRouteParameterKey>[authProviderRouteParameter],
);

/// Namespaced request data supplied to a portable auth endpoint.
final class AuthEndpointRequest {
  const AuthEndpointRequest.empty()
    : path = const <AuthRouteParameterKey, String>{},
      query = const <String, dynamic>{},
      body = const <String, dynamic>{},
      headers = const <String, String>{};

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

  final Map<AuthRouteParameterKey, String> path;
  final Map<String, dynamic> query;
  final Map<String, dynamic> body;

  /// Host-allowlisted headers exposed to portable handlers.
  ///
  /// Framework adapters are not required to forward arbitrary request
  /// headers. Routed currently forwards only `Authorization`.
  final Map<String, String> headers;

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
enum AuthOperationAuthentication { none, session, apiKey, bearer }

enum AuthOperationOriginPolicy { none, browser }

enum AuthOperationCsrfPolicy { none, required }

/// Whether an auth endpoint observes state or changes it.
///
/// Every endpoint descriptor must choose one of the two variants explicitly.
/// This keeps newly-added custom and host-owned endpoints from silently
/// bypassing persistence and replay-safety review.
sealed class AuthOperationSemantics {
  const AuthOperationSemantics();

  const factory AuthOperationSemantics.readOnly() =
      AuthReadOnlyOperationSemantics;

  const factory AuthOperationSemantics.mutation({
    required AuthMutationPersistence persistence,
    required AuthMutationReplaySafety replaySafety,
  }) = AuthMutationOperationSemantics;
}

/// A state-observing endpoint.
final class AuthReadOnlyOperationSemantics extends AuthOperationSemantics {
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
enum AuthMutationAtomicity { atomic, nonAtomic, notApplicable }

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
  const AuthPersistenceOperationReference({
    required this.schemaId,
    this.atomicOperationId,
  });

  final String schemaId;
  final String? atomicOperationId;
}

/// Typed persistence semantics for a state-changing auth operation.
final class AuthMutationPersistence {
  const AuthMutationPersistence._({
    required this.kind,
    required this.atomicity,
    this.reference,
  });

  const AuthMutationPersistence.durable({
    required AuthMutationAtomicity atomicity,
    AuthPersistenceOperationReference? reference,
  }) : this._(
         kind: AuthMutationPersistenceKind.durable,
         atomicity: atomicity,
         reference: reference,
       );

  const AuthMutationPersistence.session()
    : this._(
        kind: AuthMutationPersistenceKind.session,
        atomicity: AuthMutationAtomicity.notApplicable,
      );

  const AuthMutationPersistence.boundedEphemeral()
    : this._(
        kind: AuthMutationPersistenceKind.boundedEphemeral,
        atomicity: AuthMutationAtomicity.notApplicable,
      );

  const AuthMutationPersistence.external()
    : this._(
        kind: AuthMutationPersistenceKind.external,
        atomicity: AuthMutationAtomicity.notApplicable,
      );

  final AuthMutationPersistenceKind kind;
  final AuthMutationAtomicity atomicity;
  final AuthPersistenceOperationReference? reference;
}

/// A state-changing endpoint with explicit persistence and replay behavior.
final class AuthMutationOperationSemantics extends AuthOperationSemantics {
  const AuthMutationOperationSemantics({
    required this.persistence,
    required this.replaySafety,
  });

  final AuthMutationPersistence persistence;
  final AuthMutationReplaySafety replaySafety;
}

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
    this.request = const AuthEndpointRequest.empty(),
    this.emailVerified = false,
    this.activeOrganizationId,
    this.activeTeamId,
    this.writeActiveSelection,
    this.sessionControl,
  });

  final TContext context;
  final AuthUser? user;
  final AuthEndpointRequest request;
  final bool emailVerified;
  final String? activeOrganizationId;
  final String? activeTeamId;
  final FutureOr<void> Function(String? organizationId, String? teamId)?
  writeActiveSelection;
  final AuthServerPluginSessionControl? sessionControl;

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
  const AuthEndpointRedirect({
    required this.location,
    this.statusCode = 302,
    this.headers = const <String, String>{},
  });

  final Uri location;
  final int statusCode;
  final Map<String, String> headers;
}

/// An explicit HTTP response returned by a portable plugin endpoint.
///
/// Most auth operations return JSON with status 200. Protocol plugins that
/// require another success status, response headers, or an empty body can use
/// this value without coupling themselves to a framework response class.
final class AuthEndpointHttpResponse {
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

  final int statusCode;
  final Object? body;
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
  const AuthServerPluginDataContract({
    this.authenticationMethodNamespace,
    this.userDataNamespace,
    this.removalEndpointIds = const <String>[],
  });

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
  AuthRoutePath get path;
  AuthEndpointMount get mount;
  AuthOperationSemantics get semantics;
  AuthOperationAuthentication get authentication;
  AuthOperationOriginPolicy get originPolicy;
  AuthOperationCsrfPolicy get csrfPolicy;
  AuthRateLimitOperation? get rateLimitOperation;
  bool get serverOnly;

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
  bool get requiresRecentAuthentication;
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
  String? resolveRateLimitIdentifier(AuthEndpointRequest request);
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

/// One explicit HTTP response advertised by a portable plugin operation.
///
/// Protocol plugins use this to publish non-200 success responses, empty
/// responses, and protocol-specific error media types without coupling their
/// implementation to an OpenAPI package.
final class AuthEndpointResponseContract {
  const AuthEndpointResponseContract({
    required this.statusCode,
    required this.description,
    this.contract,
  }) : assert(statusCode >= 100 && statusCode <= 599);

  final int statusCode;
  final String description;
  final AuthOperationContract? contract;
}

/// Optional complete HTTP response contract for an endpoint.
abstract interface class AuthEndpointResponseContractDescriptor {
  Iterable<AuthEndpointResponseContract> get responseContracts;
}

/// Host-level failure that happened outside a plugin handler.
enum AuthEndpointPublicErrorKind { invalidRequest, internalFailure }

typedef AuthEndpointPublicErrorResponseFactory =
    AuthEndpointHttpResponse Function(AuthEndpointPublicErrorKind kind);

/// Optional protocol-specific public errors for failures owned by the host.
abstract interface class AuthEndpointPublicErrorResponseDescriptor {
  AuthEndpointHttpResponse? createPublicErrorResponse(
    AuthEndpointPublicErrorKind kind,
  );
}

final class TypedAuthEndpointDescriptor<TContext, TRequest, TResponse>
    implements
        AuthEndpointDescriptor<TContext>,
        AuthEndpointSecurityDescriptor,
        AuthEndpointContractDescriptor,
        AuthEndpointResponseContractDescriptor,
        AuthEndpointPublicErrorResponseDescriptor,
        AuthEndpointRateLimitIdentifierDescriptor {
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

  @override
  final String id;
  @override
  final AuthOperationMethod method;
  @override
  final AuthRoutePath path;
  @override
  final AuthEndpointMount mount;
  @override
  final AuthOperationSemantics semantics;
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
  final bool requiresRecentAuthentication;
  @override
  final Iterable<AuthEndpointResponseContract> responseContracts;
  final AuthEndpointPublicErrorResponseFactory? publicErrorResponse;
  @override
  final bool serverOnly;

  @override
  AuthEndpointHttpResponse? createPublicErrorResponse(
    AuthEndpointPublicErrorKind kind,
  ) => publicErrorResponse?.call(kind);

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
    this.mount = AuthEndpointMount.auth,
  });

  final String id;
  final AuthOperationMethod method;
  final AuthRoutePath path;
  final bool serverOnly;
  final AuthEndpointMount mount;
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
    this.authenticationMethods,
    this.passwordHasher,
    this.passwordPolicy = const PasswordPolicy(),
    this.sessionStrategy = AuthSessionStrategy.session,
  });

  final AuthStore store;
  final AuthAuthenticationMethodService? authenticationMethods;
  final PasswordHasher? passwordHasher;
  final PasswordPolicy passwordPolicy;
  final AuthSessionStrategy sessionStrategy;
}

abstract interface class AuthServerPlugin<TContext> {
  String get id;

  AuthServerPluginDataContract get dataContract;

  void configure(AuthServerPluginContext<TContext> context);
}

/// Optional plugin check executed whenever auth boots in production posture.
abstract interface class AuthProductionPostureContributor {
  void validateProductionPosture();
}

class AuthServerPluginRegistry<TContext> {
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
        authenticationMethods: _authenticationMethods,
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
      final inventoryEnabled = inventory == null
          ? false
          : plugin is AuthAuthenticationMethodInventoryControl
          ? (plugin as AuthAuthenticationMethodInventoryControl)
                .authenticationMethodInventoryEnabled
          : true;
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
        case AuthHistoricalUserDeletionNamespaceCoordinator capability) {
      capability.bindHistoricalUserDeletionNamespaces(
        _historicalUserDataNamespaces,
      );
    } else {
      throw StateError(
        'The auth store cannot guard historical user-data namespaces.',
      );
    }
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
