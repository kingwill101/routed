import 'dart:io';

import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:server_auth/server_auth.dart'
    show AuthConfig, AuthProviderRegistry;
import 'package:routed/src/config/schema.dart';

import '../spec.dart';

const List<String> _defaultJwtAlgorithms = ['RS256'];

class AuthConfigSpec extends ConfigSpec<AuthConfig> {
  const AuthConfigSpec();

  @override
  String get root => 'auth';

  @override
  Schema? get schema => ConfigSchema.object(
    title: 'Authentication Configuration',
    description: 'JWT, OAuth2, and session-based authentication settings.',
    properties: {
      'jwt': ConfigSchema.object(
        description: 'JWT Bearer authentication settings.',
        properties: {
          'enabled': ConfigSchema.boolean(
            description: 'Enable JWT Bearer authentication middleware.',
            defaultValue: false,
          ),
          'issuer': ConfigSchema.string(
            description: 'Required issuer claim value.',
          ),
          'audience': ConfigSchema.list(
            description: 'Allowed audience values (any match passes).',
            items: ConfigSchema.string(),
            defaultValue: const [],
          ),
          'required_claims': ConfigSchema.list(
            description: 'Claims that must be present in every token.',
            items: ConfigSchema.string(),
            defaultValue: const [],
          ),
          'jwks_url': ConfigSchema.string(
            description: 'JWKS endpoint used to resolve signing keys.',
          ),
          'jwks_cache_ttl': ConfigSchema.duration(
            description: 'How long JWKS responses are cached.',
            defaultValue: '5m',
          ),
          'algorithms': ConfigSchema.list(
            description: 'Allowed signing algorithms (e.g. RS256).',
            items: ConfigSchema.string(),
            defaultValue: _defaultJwtAlgorithms,
          ),
          'clock_skew': ConfigSchema.duration(
            description: 'Clock skew allowance for exp/nbf validation.',
            defaultValue: '60s',
          ),
          'keys': ConfigSchema.list(
            description: 'Inline JWK set used in addition to remote JWKS.',
            items: ConfigSchema.object(additionalProperties: true),
            defaultValue: const [],
          ),
          'header': ConfigSchema.string(
            description: 'Header name inspected for bearer tokens.',
            defaultValue: 'Authorization',
          ),
          'bearer_prefix': ConfigSchema.string(
            description:
                'Expected prefix for bearer tokens (default "Bearer ").',
            defaultValue: 'Bearer ',
          ),
        },
      ),
      'oauth2': ConfigSchema.object(
        description: 'OAuth2 authentication settings.',
        properties: {
          'introspection': ConfigSchema.object(
            description: 'RFC 7662 token introspection middleware settings.',
            properties: {
              'enabled': ConfigSchema.boolean(
                description: 'Enable RFC 7662 token introspection middleware.',
                defaultValue: false,
              ),
              'endpoint': ConfigSchema.string(
                description: 'OAuth2 introspection endpoint URL.',
              ),
              'client_id': ConfigSchema.string(
                description:
                    'Client identifier used when calling the introspection endpoint.',
              ),
              'client_secret': ConfigSchema.string(
                description: 'Client secret used for introspection requests.',
              ),
              'token_type_hint': ConfigSchema.string(
                description:
                    'Optional token type hint passed to the introspection endpoint.',
              ),
              'cache_ttl': ConfigSchema.duration(
                description: 'How long introspection results are cached.',
                defaultValue: '30s',
              ),
              'clock_skew': ConfigSchema.duration(
                description:
                    'Clock skew allowance for introspection timestamps.',
                defaultValue: '60s',
              ),
              'additional': ConfigSchema.object(
                description:
                    'Additional form parameters appended to introspection requests.',
                additionalProperties: true,
              ).withDefault(const {}),
            },
          ),
        },
      ),
      'providers': _providersSchema(),
      'session': ConfigSchema.object(
        description: 'Session-based authentication settings.',
        properties: {
          'strategy': ConfigSchema.string(
            description: 'Preferred session strategy (session or jwt).',
            options: const ['session', 'jwt'],
          ),
          'max_age': ConfigSchema.duration(
            description: 'Maximum lifetime for sessions.',
          ),
          'update_age': ConfigSchema.duration(
            description: 'How often session state should be refreshed.',
          ),
          'remember_me': ConfigSchema.object(
            description: 'Remember-me token settings.',
            properties: {
              'cookie': ConfigSchema.string(
                description: 'Cookie name used for remember-me tokens.',
                defaultValue: 'remember_token',
              ),
              'duration': ConfigSchema.duration(
                description:
                    'Default lifetime applied to remember-me tokens when issued.',
                defaultValue: '30d',
              ),
            },
          ),
        },
      ),
      'callbacks': ConfigSchema.object(
        description:
            'Auth callback hooks (sign_in, redirect, jwt, session) backed by the event system.',
        properties: {
          'sign_in': ConfigSchema.string(
            description: 'Event handler name for sign-in callbacks.',
          ),
          'redirect': ConfigSchema.string(
            description: 'Event handler name for redirect callbacks.',
          ),
          'jwt': ConfigSchema.string(
            description: 'Event handler name for JWT callbacks.',
          ),
          'session': ConfigSchema.string(
            description: 'Event handler name for session callbacks.',
          ),
        },
      ).withDefault(const {}),
      'events': ConfigSchema.object(
        description: 'Auth lifecycle events emitted via the event system.',
        properties: {
          'sign_in': ConfigSchema.list(
            description: 'Handlers invoked after successful sign-in.',
            items: ConfigSchema.string(),
          ),
          'sign_out': ConfigSchema.list(
            description: 'Handlers invoked after sign-out.',
            items: ConfigSchema.string(),
          ),
          'create_user': ConfigSchema.list(
            description: 'Handlers invoked when users are created.',
            items: ConfigSchema.string(),
          ),
          'update_user': ConfigSchema.list(
            description: 'Handlers invoked when users are updated.',
            items: ConfigSchema.string(),
          ),
          'link_account': ConfigSchema.list(
            description: 'Handlers invoked when accounts are linked.',
            items: ConfigSchema.string(),
          ),
          'session': ConfigSchema.list(
            description: 'Handlers invoked when sessions are checked.',
            items: ConfigSchema.string(),
          ),
        },
      ).withDefault(const {}),
      'features': ConfigSchema.object(
        description: 'Authentication feature flags.',
        properties: {
          'haigate': ConfigSchema.object(
            properties: {
              'enabled': ConfigSchema.boolean(
                description:
                    'Enable Haigate authorization registry and middleware.',
                defaultValue: false,
              ),
            },
          ),
        },
      ),
      'gates': ConfigSchema.object(
        description: 'Haigate authorization settings.',
        properties: {
          'defaults': ConfigSchema.object(
            properties: {
              'denied_status': ConfigSchema.integer(
                description:
                    'HTTP status returned when a gate denies access (used by default middleware).',
                defaultValue: HttpStatus.forbidden,
              ),
              'denied_message': ConfigSchema.string(
                description:
                    'Optional body message returned when a gate denies access (used by default middleware).',
              ),
            },
          ),
          'abilities': ConfigSchema.object(
            description:
                'Declarative Haigate abilities. Entries map ability names to role or authentication checks.',
            additionalProperties: true,
          ).withDefault(const {}),
        },
      ),
      'guards':
          ConfigSchema.object(
            description:
                'Named guard definitions consumed by guard middleware (e.g. authenticated, roles).',
            additionalProperties: true,
          ).withDefault(const {
            'authenticated': {'type': 'authenticated', 'realm': 'Restricted'},
          }),
    },
  );

  Schema _providersSchema() {
    final registry = AuthProviderRegistry.instance;
    return ConfigSchema.object(
      description: 'OAuth provider configurations for auth routes.',
      properties: registry.schemaEntries(),
      additionalProperties: true,
    ).withDefault(const {});
  }

  @override
  AuthConfig fromMap(Map<String, dynamic> map, {ConfigSpecContext? context}) {
    return AuthConfig.fromMap(map);
  }

  @override
  Map<String, dynamic> toMap(AuthConfig value) {
    return {
      'jwt': {
        'enabled': value.jwt.enabled,
        'issuer': value.jwt.issuer,
        'audience': value.jwt.audience,
        'required_claims': value.jwt.requiredClaims,
        'jwks_url': value.jwt.jwksUri?.toString(),
        'jwks_cache_ttl': value.jwt.jwksCacheTtl,
        'algorithms': value.jwt.algorithms,
        'clock_skew': value.jwt.clockSkew,
        'keys': value.jwt.inlineKeys,
        'header': value.jwt.header,
        'bearer_prefix': value.jwt.bearerPrefix,
      },
      'oauth2': {
        'introspection': {
          'enabled': value.oauth2Introspection.enabled,
          'endpoint': value.oauth2Introspection.endpoint?.toString(),
          'client_id': value.oauth2Introspection.clientId,
          'client_secret': value.oauth2Introspection.clientSecret,
          'token_type_hint': value.oauth2Introspection.tokenTypeHint,
          'cache_ttl': value.oauth2Introspection.cacheTtl,
          'clock_skew': value.oauth2Introspection.clockSkew,
          'additional': value.oauth2Introspection.additionalParameters,
        },
      },
      'providers': value.providers,
      'session': {
        'strategy': value.session.strategy?.name,
        'max_age': value.session.maxAge,
        'update_age': value.session.updateAge,
        'remember_me': {
          'cookie': value.sessionRememberMe.cookieName,
          'duration': value.sessionRememberMe.duration,
        },
      },
      'callbacks': {
        'sign_in': value.callbacks.signIn,
        'redirect': value.callbacks.redirect,
        'jwt': value.callbacks.jwt,
        'session': value.callbacks.session,
      },
      'events': {
        'sign_in': value.events.signIn,
        'sign_out': value.events.signOut,
        'create_user': value.events.createUser,
        'update_user': value.events.updateUser,
        'link_account': value.events.linkAccount,
        'session': value.events.session,
      },
      'features': {
        'haigate': {'enabled': value.haigate.enabled},
      },
      'gates': {
        'defaults': {
          'denied_status': value.haigate.defaults.statusCode,
          'denied_message': value.haigate.defaults.message,
        },
        'abilities': value.haigate.abilities.map(
          (key, definition) => MapEntry(key, definition.toMap()),
        ),
      },
      'guards': value.guards.map(
        (key, definition) => MapEntry(key, definition.toMap()),
      ),
    };
  }
}
