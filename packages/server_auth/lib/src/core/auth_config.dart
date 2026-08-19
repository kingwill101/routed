import 'dart:io';

import 'gates.dart';
import 'guards.dart';
import 'models.dart';

/// Normalized auth configuration consumed by framework adapters.
class AuthConfig {
  const AuthConfig({
    required this.jwt,
    required this.oauth2Introspection,
    required this.session,
    required this.haigate,
    required this.guards,
  });

  /// Returns the safe default configuration for an adapter.
  ///
  /// Applications should construct the nested configuration objects directly
  /// when they need to override a value. No file, environment, or string-path
  /// lookup is performed here.
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

  final AuthJwtConfig jwt;
  final OAuthIntrospectionConfig oauth2Introspection;
  final AuthSessionConfig session;
  final HaigateConfig haigate;
  final Map<String, GuardDefinition> guards;
}

class AuthJwtConfig {
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

  final bool enabled;
  final String? issuer;
  final List<String> audience;
  final List<String> requiredClaims;
  final Uri? jwksUri;
  final Duration jwksCacheTtl;
  final Duration clockSkew;
  final List<String> algorithms;
  final List<Map<String, dynamic>> inlineKeys;
  final String header;
  final String bearerPrefix;
}

class OAuthIntrospectionConfig {
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

  final bool enabled;
  final Uri? endpoint;
  final String? clientId;
  final String? clientSecret;
  final String? tokenTypeHint;
  final Duration cacheTtl;
  final Duration clockSkew;
  final Map<String, String> additionalParameters;
}

class SessionRememberMeConfig {
  const SessionRememberMeConfig({
    required this.cookieName,
    required this.duration,
  });

  final String? cookieName;
  final Duration duration;
}

class AuthSessionConfig {
  const AuthSessionConfig({
    required this.strategy,
    required this.maxAge,
    required this.updateAge,
    required this.rememberMe,
  });

  final AuthSessionStrategy? strategy;
  final Duration? maxAge;
  final Duration? updateAge;
  final SessionRememberMeConfig rememberMe;
}

class HaigateConfig {
  const HaigateConfig({
    required this.enabled,
    required this.defaults,
    required this.abilities,
  });

  final bool enabled;
  final GateDefaults defaults;
  final Map<String, GateDefinition> abilities;
}

class GateDefaults {
  const GateDefaults({required this.statusCode, this.message});

  final int statusCode;
  final String? message;
}

enum GateType { authenticated, guest, roles }

class GateDefinition {
  const GateDefinition.authenticated()
    : type = GateType.authenticated,
      roles = const [],
      any = false,
      allowGuest = false;

  const GateDefinition.guest()
    : type = GateType.guest,
      roles = const [],
      any = false,
      allowGuest = false;

  const GateDefinition.roles({
    required this.roles,
    this.any = false,
    this.allowGuest = false,
  }) : type = GateType.roles;

  final GateType type;
  final List<String> roles;
  final bool any;
  final bool allowGuest;
}

enum GuardType { authenticated, roles }

class GuardDefinition {
  const GuardDefinition.authenticated({this.realm = 'Restricted'})
    : type = GuardType.authenticated,
      roles = const [],
      any = false;

  const GuardDefinition.roles({required this.roles, this.any = false})
    : type = GuardType.roles,
      realm = null;

  final GuardType type;
  final List<String> roles;
  final bool any;
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
