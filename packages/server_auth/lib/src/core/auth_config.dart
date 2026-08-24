import 'dart:io';

import 'gates.dart';
import 'guards.dart';
import 'models.dart';

/// Normalized, typed authentication configuration consumed by framework adapters.
class AuthConfig {
  /// Creates a configuration from complete typed sections.
  const AuthConfig({
    required this.jwt,
    required this.oauth2Introspection,
    required this.session,
    required this.haigate,
    required this.guards,
  });

  /// Returns the safe default configuration for an adapter.
  ///
  /// JWT, introspection, and Haigate are disabled; session strategy and guards
  /// are unset; required JWT claims contain `exp`; and remember-me defaults to
  /// a `remember_token` cookie lasting 30 days. No file, environment, or
  /// string-path lookup is performed here.
  factory AuthConfig.defaults() => AuthConfig(
    jwt: const AuthJwtConfig(
      enabled: false,
      issuer: null,
      audience: <String>[],
      requiredClaims: <String>['exp'],
      jwksUri: null,
      jwksCacheTtl: Duration(minutes: 5),
      clockSkew: Duration(seconds: 60),
      algorithms: <String>['RS256'],
      inlineKeys: <Map<String, dynamic>>[],
      header: 'Authorization',
      bearerPrefix: 'Bearer ',
    ),
    oauth2Introspection: const OAuthIntrospectionConfig(
      enabled: false,
      endpoint: null,
      clientId: null,
      clientSecret: null,
      tokenTypeHint: null,
      cacheTtl: Duration.zero,
      clockSkew: Duration(seconds: 60),
      additionalParameters: <String, String>{},
    ),
    session: AuthSessionConfig(
      strategy: null,
      maxAge: null,
      updateAge: null,
      rememberMe: const SessionRememberMeConfig(
        cookieName: 'remember_token',
        duration: Duration(days: 30),
      ),
    ),
    haigate: const HaigateConfig(
      enabled: false,
      defaults: GateDefaults(statusCode: HttpStatus.forbidden),
      abilities: <String, GateDefinition>{},
    ),
    guards: const <String, GuardDefinition>{},
  );

  /// Returns a copy with selected typed configuration sections replaced.
  ///
  /// Each supplied section replaces the complete section; nested values are
  /// not merged.
  AuthConfig copyWith({
    AuthJwtConfig? jwt,
    OAuthIntrospectionConfig? oauth2Introspection,
    AuthSessionConfig? session,
    HaigateConfig? haigate,
    Map<String, GuardDefinition>? guards,
  }) {
    return AuthConfig(
      jwt: jwt ?? this.jwt,
      oauth2Introspection: oauth2Introspection ?? this.oauth2Introspection,
      session: session ?? this.session,
      haigate: haigate ?? this.haigate,
      guards: guards ?? this.guards,
    );
  }

  /// JWT verification and bearer-token settings.
  final AuthJwtConfig jwt;

  /// OAuth 2.0 token-introspection settings.
  final OAuthIntrospectionConfig oauth2Introspection;

  /// Session strategy, lifetime, and remember-me settings.
  final AuthSessionConfig session;

  /// Haigate ability and denial-response settings.
  final HaigateConfig haigate;

  /// Named guard definitions used by framework adapters.
  final Map<String, GuardDefinition> guards;
}

/// JWT verification settings for adapter-managed bearer authentication.
class AuthJwtConfig {
  /// Creates JWT settings.
  const AuthJwtConfig({
    required this.enabled,
    required this.issuer,
    required this.audience,
    required this.requiredClaims,
    required this.jwksUri,
    required this.jwksCacheTtl,
    required this.clockSkew,
    required this.algorithms,
    required this.inlineKeys,
    required this.header,
    required this.bearerPrefix,
  });

  /// Whether JWT verification is enabled.
  final bool enabled;

  /// Issuer claim required from verified tokens, when configured.
  final String? issuer;

  /// Audience values accepted from verified tokens.
  final List<String> audience;

  /// Claims that every verified token must contain.
  final List<String> requiredClaims;

  /// JWKS endpoint used to resolve signing keys.
  final Uri? jwksUri;

  /// Duration for which fetched JWKS data may be cached.
  final Duration jwksCacheTtl;

  /// Clock tolerance applied to time-based claims.
  final Duration clockSkew;

  /// Signing algorithms accepted by the verifier.
  final List<String> algorithms;

  /// Inline JWK maps available without a network lookup.
  final List<Map<String, dynamic>> inlineKeys;

  /// Header containing the bearer value.
  final String header;

  /// Prefix required before the bearer token in [header].
  final String bearerPrefix;
}

/// OAuth 2.0 token-introspection settings.
class OAuthIntrospectionConfig {
  /// Creates introspection settings.
  const OAuthIntrospectionConfig({
    required this.enabled,
    required this.endpoint,
    required this.clientId,
    required this.clientSecret,
    required this.tokenTypeHint,
    required this.cacheTtl,
    required this.clockSkew,
    required this.additionalParameters,
  });

  /// Whether introspection requests are enabled.
  final bool enabled;

  /// Introspection endpoint receiving token checks.
  final Uri? endpoint;

  /// Client identifier sent to the introspection endpoint.
  final String? clientId;

  /// Client secret sent to the introspection endpoint.
  final String? clientSecret;

  /// Optional `token_type_hint` value.
  final String? tokenTypeHint;

  /// Duration for which a successful introspection may be cached.
  final Duration cacheTtl;

  /// Clock tolerance applied to introspection timestamps.
  final Duration clockSkew;

  /// Additional form parameters sent with each introspection request.
  final Map<String, String> additionalParameters;
}

/// Remember-me cookie settings for session authentication.
class SessionRememberMeConfig {
  /// Creates remember-me settings.
  const SessionRememberMeConfig({
    required this.cookieName,
    required this.duration,
  });

  /// Name of the remember-me cookie, or null to disable it.
  final String? cookieName;

  /// Lifetime assigned to remember-me credentials.
  final Duration duration;
}

/// Session authentication strategy and lifetime settings.
class AuthSessionConfig {
  /// Creates session settings.
  const AuthSessionConfig({
    required this.strategy,
    required this.maxAge,
    required this.updateAge,
    required this.rememberMe,
  });

  /// Session strategy, or null when the adapter chooses its default.
  final AuthSessionStrategy? strategy;

  /// Maximum session lifetime, or null for the adapter default.
  final Duration? maxAge;

  /// Minimum interval before issued-at metadata is refreshed.
  final Duration? updateAge;

  /// Remember-me behavior associated with this session strategy.
  final SessionRememberMeConfig rememberMe;
}

/// Haigate authorization settings.
class HaigateConfig {
  /// Creates Haigate settings.
  const HaigateConfig({
    required this.enabled,
    required this.defaults,
    required this.abilities,
  });

  /// Whether Haigate integration is enabled.
  final bool enabled;

  /// Default status and message for denied abilities.
  final GateDefaults defaults;

  /// Named ability definitions resolved by [resolveConfiguredGateCallback].
  final Map<String, GateDefinition> abilities;
}

/// Default HTTP response details for a denied gate.
class GateDefaults {
  /// Creates denial defaults with an HTTP [statusCode] and optional [message].
  const GateDefaults({required this.statusCode, this.message});

  /// Status returned when a gate denies access.
  final int statusCode;

  /// Optional public denial message.
  final String? message;
}

/// Kind of gate applied to a request.
enum GateType {
  /// Requires an authenticated principal.
  authenticated,

  /// Requires an unauthenticated request.
  guest,

  /// Requires one or more roles.
  roles,
}

/// Declarative definition of a named authorization gate.
class GateDefinition {
  /// Creates a gate requiring an authenticated principal.
  const GateDefinition.authenticated()
    : type = GateType.authenticated,
      roles = const [],
      any = false,
      allowGuest = false;

  /// Creates a gate requiring an unauthenticated request.
  const GateDefinition.guest()
    : type = GateType.guest,
      roles = const [],
      any = false,
      allowGuest = false;

  /// Creates a gate requiring the configured [roles].
  const GateDefinition.roles({
    required this.roles,
    this.any = false,
    this.allowGuest = false,
  }) : type = GateType.roles;

  /// Gate kind selected by the named constructors.
  final GateType type;

  /// Roles checked when [type] is [GateType.roles].
  final List<String> roles;

  /// Whether any role may satisfy the definition instead of all roles.
  final bool any;

  /// Whether an anonymous principal may pass a role gate.
  final bool allowGuest;
}

/// Kind of response-producing authentication guard.
enum GuardType {
  /// Challenges requests that are not authenticated.
  authenticated,

  /// Authorizes requests by role membership.
  roles,
}

/// Declarative definition of a named authentication guard.
class GuardDefinition {
  /// Creates an authenticated guard using [realm] for its challenge.
  const GuardDefinition.authenticated({this.realm = 'Restricted'})
    : type = GuardType.authenticated,
      roles = const [],
      any = false;

  /// Creates a role guard requiring the configured [roles].
  const GuardDefinition.roles({required this.roles, this.any = false})
    : type = GuardType.roles,
      realm = null;

  /// Guard kind selected by the named constructors.
  final GuardType type;

  /// Roles checked when [type] is [GuardType.roles].
  final List<String> roles;

  /// Whether any role may satisfy the definition instead of all roles.
  final bool any;

  /// Challenge realm for an authenticated guard.
  final String? realm;
}

/// Resolves a generic auth gate callback from [definition].
AuthGateCallback<TContext>? resolveConfiguredGateCallback<TContext>(
  GateDefinition definition,
) {
  switch (definition.type) {
    case GateType.guest:
      return guestGate<TContext>();
    case GateType.authenticated:
      return authenticatedGate<TContext>();
    case GateType.roles:
      return rolesGate<TContext>(
        definition.roles,
        any: definition.any,
        allowGuest: definition.allowGuest,
      );
  }
}

/// Resolves a generic auth guard from [definition].
///
/// Returns `null` when a role guard has no roles to check.
AuthGuard<TContext, TResponse>? resolveConfiguredGuard<TContext, TResponse>({
  required GuardDefinition definition,
  required AuthGuard<TContext, TResponse> Function(String realm)
  authenticatedGuard,
  required AuthGuard<TContext, TResponse> Function(List<String> roles, bool any)
  rolesGuard,
}) {
  switch (definition.type) {
    case GuardType.authenticated:
      final realm = definition.realm == null || definition.realm!.trim().isEmpty
          ? 'Restricted'
          : definition.realm!;
      return authenticatedGuard(realm);
    case GuardType.roles:
      if (definition.roles.isEmpty) {
        return null;
      }
      return rolesGuard(definition.roles, definition.any);
  }
}
