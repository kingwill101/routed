import 'dart:convert';
import 'dart:io';

import 'package:routed/src/auth/manager.dart';
import 'package:routed/src/auth/models.dart';
import 'package:routed/src/auth/providers.dart';
import 'package:routed/src/context/context.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/router/router.dart';

const Map<String, Object?> _authProviderSchema = {
  'type': 'object',
  'properties': {
    'id': {'type': 'string'},
    'name': {'type': 'string'},
    'type': {
      'type': 'string',
      'enum': ['oauth', 'email', 'credentials'],
    },
  },
  'required': ['id', 'name', 'type'],
};

const Map<String, Object?> _authUserSchema = {
  'type': 'object',
  'properties': {
    'id': {'type': 'string'},
    'email': {
      'type': ['string', 'null'],
    },
    'name': {
      'type': ['string', 'null'],
    },
    'image': {
      'type': ['string', 'null'],
    },
    'roles': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'attributes': {'type': 'object', 'additionalProperties': true},
  },
  'required': ['id'],
};

const Map<String, Object?> _authSessionSchema = {
  'type': 'object',
  'properties': {
    'user': _authUserSchema,
    'expires': {
      'type': ['string', 'null'],
      'format': 'date-time',
    },
    'strategy': {
      'type': ['string', 'null'],
      'enum': ['session', 'jwt', null],
    },
    'token': {
      'type': ['string', 'null'],
    },
  },
  'required': ['user'],
};

const Map<String, Object?> _nullableSessionSchema = {
  'oneOf': [
    _authSessionSchema,
    {'type': 'null'},
  ],
};

const Map<String, Object?> _authProvidersResponseSchema = {
  'type': 'object',
  'properties': {
    'providers': {'type': 'array', 'items': _authProviderSchema},
  },
  'required': ['providers'],
};

const Map<String, Object?> _authCsrfSchema = {
  'type': 'object',
  'properties': {
    'csrfToken': {'type': 'string'},
  },
  'required': ['csrfToken'],
};

const Map<String, Object?> _authErrorSchema = {
  'type': 'object',
  'properties': {
    'error': {'type': 'string'},
  },
  'required': ['error'],
};

const Map<String, Object?> _authPayloadSchema = {
  'type': 'object',
  'properties': {
    'email': {'type': 'string'},
    'username': {'type': 'string'},
    'password': {'type': 'string'},
    'callbackUrl': {'type': 'string'},
    'redirect': {'type': 'string'},
    '_csrf': {'type': 'string'},
  },
  'additionalProperties': true,
};

const Map<String, Object?> _authSignOutSchema = {
  'type': 'object',
  'properties': {
    'ok': {'type': 'boolean'},
  },
  'required': ['ok'],
};

const Map<String, Object?> _authRedirectHeaderSchema = {
  'description': 'Redirect target URL',
  'schema': {'type': 'string'},
};

/// Auth HTTP routes for routed.
///
/// ## Routes
/// - `GET /providers` lists configured providers.
/// - `GET /csrf` issues CSRF tokens.
/// - `GET /session` returns the current session.
/// - `GET|POST /signin/{provider}` begins sign-in.
/// - `POST /register/{provider}` registers new credentials.
/// - `GET /callback/{provider}` completes OAuth/email flows.
/// - `POST /signout` signs the user out.
///
/// ## Usage
/// ```dart
/// final routes = AuthRoutes(manager);
/// routes.register(engine.defaultRouter);
/// ```
class AuthRoutes {
  AuthRoutes(this.manager);

  final AuthManager manager;

  void register(Router router, {String? basePath}) {
    final root = basePath ?? manager.options.basePath;
    router.group(
      path: root,
      builder: (auth) {
        auth.get('/providers', _providers).openApi((spec) {
          spec
            ..summary = 'List configured auth providers'
            ..tags(['auth'])
            ..jsonResponse(
              status: '200',
              description: 'Provider metadata returned by auth providers.',
              schema: _authProvidersResponseSchema,
            );
        });
        auth.get('/csrf', _csrf).openApi((spec) {
          spec
            ..summary = 'Fetch CSRF token'
            ..tags(['auth'])
            ..jsonResponse(
              status: '200',
              description: 'CSRF token payload.',
              schema: _authCsrfSchema,
            );
        });
        auth.get('/session', _session).openApi((spec) {
          spec
            ..summary = 'Fetch current session'
            ..tags(['auth'])
            ..jsonResponse(
              status: '200',
              description: 'Current auth session or null.',
              schema: _nullableSessionSchema,
            );
        });
        auth.post('/signin/{provider}', _signIn).openApi((spec) {
          spec
            ..summary = 'Sign in with a provider'
            ..tags(['auth'])
            ..jsonRequestBody(
              schema: _authPayloadSchema,
              description:
                  'Credentials, email, or callback parameters for sign-in.',
              required: false,
            )
            ..jsonResponse(
              status: '200',
              description: 'Authenticated session payload.',
              schema: _authSessionSchema,
            )
            ..jsonResponse(
              status: '400',
              description: 'Missing provider or invalid payload.',
              schema: _authErrorSchema,
            )
            ..jsonResponse(
              status: '401',
              description: 'Unauthorized or invalid credentials.',
              schema: _authErrorSchema,
            )
            ..jsonResponse(
              status: '403',
              description: 'Invalid CSRF token.',
              schema: _authErrorSchema,
            )
            ..jsonResponse(
              status: '404',
              description: 'Unknown provider.',
              schema: _authErrorSchema,
            );
        });
        auth.get('/signin/{provider}', _signIn).openApi((spec) {
          spec
            ..summary = 'Begin OAuth sign-in'
            ..tags(['auth'])
            ..parameter(
              name: 'callbackUrl',
              location: 'query',
              description: 'Optional redirect destination after sign-in.',
            )
            ..response(
              status: '302',
              description: 'Redirect to the provider authorize URL.',
              headers: {'Location': _authRedirectHeaderSchema},
            )
            ..jsonResponse(
              status: '405',
              description: 'Method not allowed for non-OAuth providers.',
              schema: _authErrorSchema,
            )
            ..jsonResponse(
              status: '404',
              description: 'Unknown provider.',
              schema: _authErrorSchema,
            );
        });
        auth.post('/register/{provider}', _register).openApi((spec) {
          spec
            ..summary = 'Register credentials'
            ..tags(['auth'])
            ..jsonRequestBody(
              schema: _authPayloadSchema,
              description: 'Credential payload and CSRF token.',
              required: false,
            )
            ..jsonResponse(
              status: '200',
              description: 'Authenticated session payload.',
              schema: _authSessionSchema,
            )
            ..jsonResponse(
              status: '400',
              description: 'Missing provider or unsupported flow.',
              schema: _authErrorSchema,
            )
            ..jsonResponse(
              status: '401',
              description: 'Unauthorized or invalid credentials.',
              schema: _authErrorSchema,
            )
            ..jsonResponse(
              status: '403',
              description: 'Invalid CSRF token.',
              schema: _authErrorSchema,
            )
            ..jsonResponse(
              status: '404',
              description: 'Unknown provider.',
              schema: _authErrorSchema,
            );
        });
        auth.get('/callback/{provider}', _callback).openApi((spec) {
          spec
            ..summary = 'Complete provider callback'
            ..tags(['auth'])
            ..parameter(
              name: 'code',
              location: 'query',
              description: 'OAuth authorization code.',
            )
            ..parameter(
              name: 'state',
              location: 'query',
              description: 'OAuth state value.',
            )
            ..parameter(
              name: 'token',
              location: 'query',
              description: 'Email verification token.',
            )
            ..parameter(
              name: 'email',
              location: 'query',
              description: 'Email identifier for magic link sign-in.',
            )
            ..parameter(
              name: 'identifier',
              location: 'query',
              description: 'Alternate email identifier field.',
            )
            ..response(
              status: '302',
              description: 'Redirect to stored callback URL.',
              headers: {'Location': _authRedirectHeaderSchema},
            )
            ..jsonResponse(
              status: '200',
              description: 'Authenticated session payload.',
              schema: _authSessionSchema,
            )
            ..jsonResponse(
              status: '400',
              description: 'Missing required callback parameters.',
              schema: _authErrorSchema,
            )
            ..jsonResponse(
              status: '401',
              description: 'Unauthorized callback.',
              schema: _authErrorSchema,
            )
            ..jsonResponse(
              status: '404',
              description: 'Unknown provider.',
              schema: _authErrorSchema,
            );
        });
        auth.post('/signout', _signOut).openApi((spec) {
          spec
            ..summary = 'Sign out'
            ..tags(['auth'])
            ..jsonRequestBody(
              schema: _authPayloadSchema,
              description: 'CSRF token payload.',
              required: false,
            )
            ..jsonResponse(
              status: '200',
              description: 'Signed out response.',
              schema: _authSignOutSchema,
            )
            ..jsonResponse(
              status: '403',
              description: 'Invalid CSRF token.',
              schema: _authErrorSchema,
            );
        });
      },
    );
  }

  Response _providers(EngineContext ctx) {
    return ctx.json({'providers': manager.providerSummaries()});
  }

  Response _csrf(EngineContext ctx) {
    return ctx.json({'csrfToken': manager.csrfToken(ctx)});
  }

  Future<Response> _session(EngineContext ctx) async {
    final session = await manager.resolveSession(ctx);
    if (session == null) {
      return ctx.json(null);
    }
    final payload = await manager.buildSessionPayload(ctx, session);
    return ctx.json(payload);
  }

  Future<Response> _signIn(EngineContext ctx) async {
    final providerId = ctx.params['provider']?.toString();
    if (providerId == null || providerId.isEmpty) {
      return ctx.json({
        'error': 'missing_provider',
      }, statusCode: HttpStatus.badRequest);
    }

    final provider = manager.resolveProvider(providerId);
    if (provider == null) {
      return ctx.json({
        'error': 'unknown_provider',
      }, statusCode: HttpStatus.notFound);
    }

    final payload = await _payload(ctx);
    final callbackUrl = await _callbackUrl(ctx, payload, provider: provider);

    if (provider is OAuthProvider) {
      final redirectUri = await manager.beginOAuth(
        ctx,
        provider,
        callbackUrl: callbackUrl,
      );
      return await ctx.redirect(redirectUri.toString());
    }

    if (ctx.request.method == 'GET') {
      return ctx.json({
        'error': 'method_not_allowed',
      }, statusCode: HttpStatus.methodNotAllowed);
    }

    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }

    if (provider is EmailProvider) {
      final email = payload['email']?.toString();
      if (email == null || email.isEmpty) {
        return ctx.json({
          'error': 'missing_email',
        }, statusCode: HttpStatus.badRequest);
      }
      try {
        await manager.signInWithEmail(ctx, provider, email, callbackUrl ?? '');
      } on AuthFlowException catch (error) {
        return ctx.json({
          'error': error.code,
        }, statusCode: HttpStatus.unauthorized);
      }
      return ctx.json({'status': 'verification_sent', 'email': email});
    }

    if (provider is CredentialsProvider) {
      final credentials = AuthCredentials.fromMap(payload);
      try {
        final result = await manager.signInWithCredentials(
          ctx,
          provider,
          credentials,
        );
        return await _respond(ctx, result, provider: provider);
      } on AuthFlowException catch (error) {
        return ctx.json({
          'error': error.code,
        }, statusCode: HttpStatus.unauthorized);
      }
    }

    return ctx.json({
      'error': 'unsupported_provider',
    }, statusCode: HttpStatus.badRequest);
  }

  Future<Response> _register(EngineContext ctx) async {
    final providerId = ctx.params['provider']?.toString();
    if (providerId == null || providerId.isEmpty) {
      return ctx.json({
        'error': 'missing_provider',
      }, statusCode: HttpStatus.badRequest);
    }

    final provider = manager.resolveProvider(providerId);
    if (provider == null) {
      return ctx.json({
        'error': 'unknown_provider',
      }, statusCode: HttpStatus.notFound);
    }

    final payload = await _payload(ctx);
    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }

    if (provider is CredentialsProvider) {
      final credentials = AuthCredentials.fromMap(payload);
      try {
        final result = await manager.registerWithCredentials(
          ctx,
          provider,
          credentials,
        );
        return await _respond(ctx, result, provider: provider);
      } on AuthFlowException catch (error) {
        return ctx.json({
          'error': error.code,
        }, statusCode: HttpStatus.unauthorized);
      }
    }

    return ctx.json({
      'error': 'unsupported_provider',
    }, statusCode: HttpStatus.badRequest);
  }

  Future<Response> _callback(EngineContext ctx) async {
    final providerId = ctx.params['provider']?.toString();
    if (providerId == null || providerId.isEmpty) {
      return ctx.json({
        'error': 'missing_provider',
      }, statusCode: HttpStatus.badRequest);
    }

    final provider = manager.resolveProvider(providerId);
    if (provider == null) {
      return ctx.json({
        'error': 'unknown_provider',
      }, statusCode: HttpStatus.notFound);
    }

    if (provider is OAuthProvider) {
      final code = ctx.request.queryParameters['code'];
      final state = ctx.request.queryParameters['state'];
      if (code == null || code.isEmpty) {
        return ctx.json({
          'error': 'missing_code',
        }, statusCode: HttpStatus.badRequest);
      }
      try {
        final result = await manager.finishOAuth(ctx, provider, code, state);
        return await _respond(ctx, result, provider: provider);
      } on AuthFlowException catch (error) {
        return ctx.json({
          'error': error.code,
        }, statusCode: HttpStatus.unauthorized);
      }
    }

    if (provider is EmailProvider) {
      final token = ctx.request.queryParameters['token'];
      final email =
          ctx.request.queryParameters['email'] ??
          ctx.request.queryParameters['identifier'];
      if (token == null || token.isEmpty || email == null || email.isEmpty) {
        return ctx.json({
          'error': 'missing_token',
        }, statusCode: HttpStatus.badRequest);
      }
      try {
        final result = await manager.verifyEmail(ctx, provider, email, token);
        return await _respond(ctx, result, provider: provider);
      } on AuthFlowException catch (error) {
        return ctx.json({
          'error': error.code,
        }, statusCode: HttpStatus.unauthorized);
      }
    }

    return ctx.json({
      'error': 'unsupported_provider',
    }, statusCode: HttpStatus.badRequest);
  }

  Future<Response> _signOut(EngineContext ctx) async {
    final payload = await _payload(ctx);
    if (!manager.validateCsrf(ctx, payload)) {
      return ctx.json({
        'error': 'invalid_csrf',
      }, statusCode: HttpStatus.forbidden);
    }

    final session = await manager.resolveSession(ctx);

    switch (manager.options.sessionStrategy) {
      case AuthSessionStrategy.session:
        await manager.sessionAuth.logout(ctx);
        break;
      case AuthSessionStrategy.jwt:
        final cookie = Cookie(manager.options.jwtOptions.cookieName, '')
          ..maxAge = 0
          ..path = '/';
        ctx.response.cookies.add(cookie);
        break;
    }

    await manager.emitSignOut(ctx, session: session);
    return ctx.json({'ok': true});
  }

  Future<Map<String, dynamic>> _payload(EngineContext ctx) async {
    final contentType = ctx.request.contentType?.mimeType ?? '';
    if (contentType.contains('application/json')) {
      final body = await ctx.request.body();
      if (body.trim().isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{'value': decoded};
    }
    if (contentType.contains('application/x-www-form-urlencoded') ||
        contentType.contains('multipart/form-data')) {
      return await ctx.formCache;
    }

    return Map<String, dynamic>.from(ctx.queryCache);
  }

  Future<String?> _callbackUrl(
    EngineContext ctx,
    Map<String, dynamic> payload, {
    AuthProvider? provider,
  }) async {
    final candidate =
        payload['callbackUrl']?.toString() ??
        payload['redirect']?.toString() ??
        ctx.request.queryParameters['callbackUrl'];
    final sanitized = _sanitizeRedirect(ctx, candidate);
    final resolved = await manager.resolveRedirect(
      ctx,
      sanitized,
      provider: provider,
    );
    return _sanitizeRedirect(ctx, resolved ?? sanitized);
  }

  String? _sanitizeRedirect(EngineContext ctx, String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null) {
      return null;
    }
    if (!uri.isAbsolute) {
      if (!value.startsWith('/')) {
        return null;
      }
      return value;
    }

    final requestUri = ctx.request.uri;
    final sameHost = uri.host == requestUri.host;
    final sameScheme =
        uri.scheme.isEmpty || uri.scheme.toLowerCase() == requestUri.scheme;
    if (sameHost && sameScheme) {
      return uri.toString();
    }
    return null;
  }

  Future<Response> _respond(
    EngineContext ctx,
    AuthResult result, {
    AuthProvider? provider,
  }) async {
    final redirectUrl = _sanitizeRedirect(ctx, result.redirectUrl);
    if (redirectUrl != null && redirectUrl.isNotEmpty) {
      return await ctx.redirect(redirectUrl);
    }
    final payload = await manager.buildSessionPayload(
      ctx,
      result.session,
      provider: provider,
    );
    return ctx.json(payload);
  }
}
