import 'package:routed/routed.dart';
import 'package:routed_auth_cloudflare/routed_auth_cloudflare.dart';
import 'package:routed_node/cloudflare.dart';

import 'config.dart';
import 'embedded_views.dart';

const _authTablePrefix = 'routed_cloudflare_auth';

/// Creates the production Worker engine from Cloudflare's typed bindings.
///
/// This is the only host-specific factory in the application. The Worker
/// entrypoint supplies the environment, while [config] and [registerRoutes]
/// remain reusable on Dart IO and in tests.
Future<Engine> createCloudflareEngine(CloudflareEnvironment environment) async {
  final origin = Uri.parse(cloudflareTextBinding(environment, 'AUTH_ORIGIN'));
  final sessionKey = cloudflareTextBinding(environment, 'SESSION_KEY');
  final localDevelopment =
      _optionalCloudflareTextBinding(
        environment,
        'AUTH_LOCAL_DEVELOPMENT',
      )?.toLowerCase() ==
      'true';
  final store = await CloudflareD1AuthStore.open(
    environment.d1('AUTH_DB'),
    schema: const CloudflareD1AuthSchema(tablePrefix: _authTablePrefix),
  );
  return createEngine(
    store: store,
    origin: origin,
    sessionKey: sessionKey,
    socialProviders: _cloudflareSocialProviders(environment, origin),
    localDevelopment: localDevelopment,
  );
}

/// Builds the application around any durable [AuthStore].
///
/// The application factory takes typed dependencies rather than reading
/// environment variables or reaching into a host runtime. That is what lets
/// the same routes run against D1, SQLite, or an in-memory store.
Future<Engine> createEngine({
  required AuthStore store,
  required Uri origin,
  required String sessionKey,
  Iterable<AuthProvider> socialProviders = const [],
  bool localDevelopment = false,
  bool initialize = true,
}) async {
  final engine = config(
    store: store,
    origin: origin,
    sessionKey: sessionKey,
    socialProviders: socialProviders,
    localDevelopment: localDevelopment,
  ).buildEngine();

  registerRoutes(
    engine,
    storeLabel: localDevelopment ? 'in_memory' : 'cloudflare_d1',
  );
  if (initialize) {
    await engine.initialize();
  }
  return engine;
}

/// Registers the application routes after typed providers have been composed.
void registerRoutes(Engine engine, {String storeLabel = 'cloudflare_d1'}) {
  engine.addGlobalMiddleware(sessionMiddleware());
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

  engine.get('/', (context) async {
    final manager = _authManager(context);
    // Anonymous visits do not need a D1 session lookup. Apart from avoiding a
    // needless round trip, this keeps the public landing page independent of
    // the durable auth store when there is no authenticated principal.
    final principal = SessionAuth.current(context);
    final session = principal == null
        ? null
        : await manager.resolveSession(context);
    return _renderEmbeddedPage(context, 'home.liquid', <String, dynamic>{
      'title': 'Routed Cloudflare Auth',
      'description':
          'A portable Routed application using D1 for auth storage and an embedded Liquid frontend.',
      'status': 'Worker online',
      'authenticated': session != null,
      'user_email': session?.user.email ?? '',
      'csrf_token': manager.csrfToken(context),
      'routes': <Map<String, String>>[
        {'label': 'Health check', 'path': '/health'},
        {'label': 'Auth providers', 'path': '/auth/providers'},
        {'label': 'CSRF token', 'path': '/auth/csrf'},
        {'label': 'Authenticated account', 'path': '/account'},
      ],
    });
  });

  engine.get('/login', (context) async {
    if (SessionAuth.current(context) != null) {
      return context.redirect('/dashboard');
    }
    return _authPage(context, login: true);
  });
  engine.post('/login', (context) => _credentialsForm(context, login: true));

  engine.get('/signup', (context) async {
    if (SessionAuth.current(context) != null) {
      return context.redirect('/dashboard');
    }
    return _authPage(context, login: false);
  });
  engine.post('/signup', (context) => _credentialsForm(context, login: false));

  engine.post('/logout', _logout);

  engine.get('/dashboard', (context) async {
    final manager = _authManager(context);
    final session = await manager.resolveSession(context);
    final sessions = session == null
        ? const <AuthSessionInfo>[]
        : await manager.listSessions(context);
    return _renderEmbeddedPage(context, 'dashboard.liquid', <String, dynamic>{
      'csrf_token': manager.csrfToken(context),
      'email': session?.user.email ?? '',
      'name': session?.user.name ?? '',
      'user_id': session?.user.id ?? '',
      'session_strategy': session?.strategy?.name ?? 'session',
      'session_expires':
          session?.expiresAt?.toUtc().toIso8601String() ?? 'browser session',
      'sessions': sessions.map((value) => value.toJson()).toList(),
    });
  }, middlewares: [_browserAuthenticationGuard()]);

  engine.get(
    '/settings/profile',
    _profilePage,
    middlewares: [_browserAuthenticationGuard()],
  );
  engine.post(
    '/settings/profile',
    _updateProfile,
    middlewares: [_browserAuthenticationGuard()],
  );
  engine.get(
    '/settings/password',
    _passwordPage,
    middlewares: [_browserAuthenticationGuard()],
  );
  engine.post(
    '/settings/password',
    _changePassword,
    middlewares: [_browserAuthenticationGuard()],
  );
  engine.get(
    '/settings/sessions',
    _sessionsPage,
    middlewares: [_browserAuthenticationGuard()],
  );
  engine.post(
    '/settings/sessions/revoke-others',
    _revokeOtherSessions,
    middlewares: [_browserAuthenticationGuard()],
  );

  engine.get('/health', (context) {
    return context.json(<String, Object?>{
      'ok': true,
      'store': storeLabel,
      'sessions': 'encrypted_cookie',
    });
  });

  engine.get(
    '/account',
    (context) {
      final principal = SessionAuth.current(context);
      return context.json(<String, Object?>{
        'authenticated': true,
        'userId': principal?.id,
        'email': principal?.attributes['email'],
      });
    },
    middlewares: [
      guardMiddleware(['authenticated']),
    ],
  );
}

AuthManager _authManager(EngineContext context) =>
    context.container.get<AuthManager>();

Middleware _browserAuthenticationGuard() {
  return (context, next) async {
    // The framework principal is only a browser-side projection. A server
    // session can be revoked or expire while that projection remains in the
    // encrypted cookie, so protected pages must resolve the authoritative
    // session before rendering.
    final session = await _authManager(context).resolveSession(context);
    if (session == null) {
      return context.redirect('/login');
    }
    return await next();
  };
}

Future<Response> _renderEmbeddedPage(
  EngineContext context,
  String template,
  Map<String, dynamic> data, {
  int statusCode = HttpStatus.ok,
}) async {
  // Fetch hosts should resolve the embedded engine directly. The generic
  // ViewEngineManager path assumes filesystem-style template resolution,
  // which is not available in this Worker runtime.
  final content = await context.container
      .get<EmbeddedLiquidViewEngine>()
      .render(template, data);
  context.response.headers.set('Cache-Control', 'no-store, private');
  return context.html(content, statusCode: statusCode);
}

Future<Response> _profilePage(
  EngineContext context, {
  String? error,
  String? name,
  String? image,
  int statusCode = HttpStatus.ok,
}) async {
  final manager = _authManager(context);
  final session = await manager.resolveSession(context);
  if (session == null) return context.redirect('/login');
  final user = await manager.store.users.findById(session.user.id);
  if (user == null) return context.redirect('/login');
  final accounts = await manager.listLinkedAccounts(context);
  return _renderEmbeddedPage(context, 'profile.liquid', <String, dynamic>{
    'csrf_token': manager.csrfToken(context),
    'email': user.email ?? '',
    'name': name ?? user.name ?? '',
    'image': image ?? user.image ?? '',
    'accounts': accounts.map((value) => value.toJson()).toList(),
    'has_accounts': accounts.isNotEmpty,
    'error': error,
    'updated': context.request.queryParameters['updated'] == '1',
  }, statusCode: statusCode);
}

Future<Response> _passwordPage(
  EngineContext context, {
  String? error,
  int statusCode = HttpStatus.ok,
}) async {
  final manager = _authManager(context);
  final session = await manager.resolveSession(context);
  if (session == null) return context.redirect('/login');
  return _renderEmbeddedPage(context, 'password.liquid', <String, dynamic>{
    'csrf_token': manager.csrfToken(context),
    'email': session.user.email ?? '',
    'error': error,
  }, statusCode: statusCode);
}

Future<Response> _changePassword(EngineContext context) async {
  final manager = _authManager(context);
  final payload = await context.formCache;
  final currentPassword = payload['current_password']?.toString() ?? '';
  final newPassword = payload['new_password']?.toString() ?? '';
  final confirmation = payload['new_password_confirmation']?.toString() ?? '';

  final browserError = manager.validateBrowserRequest(context);
  if (browserError != null || !manager.validateCsrf(context, payload)) {
    return _passwordPage(
      context,
      error: _friendlyAuthError(browserError ?? 'invalid_csrf'),
      statusCode: HttpStatus.forbidden,
    );
  }
  if (newPassword != confirmation) {
    return _passwordPage(
      context,
      error: 'The new passwords do not match.',
      statusCode: HttpStatus.badRequest,
    );
  }

  final session = await manager.resolveSession(context);
  if (session == null) return context.redirect('/login');
  try {
    await manager.changePassword(
      context,
      identifier: session.user.email ?? '',
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    // Password changes revoke every server session, including this one.
    return await context.redirect('/login?password_changed=1');
  } on AuthFlowException catch (error) {
    return _passwordPage(
      context,
      error: _friendlyAuthError(error.code),
      statusCode: HttpStatus.badRequest,
    );
  } catch (_) {
    return _passwordPage(
      context,
      error: _friendlyAuthError('password_change_failed'),
      statusCode: HttpStatus.badRequest,
    );
  }
}

Future<Response> _updateProfile(EngineContext context) async {
  final manager = _authManager(context);
  final payload = await context.formCache;
  final submittedName = payload['name']?.toString().trim() ?? '';
  final submittedImage = payload['image']?.toString().trim() ?? '';

  final browserError = manager.validateBrowserRequest(context);
  if (browserError != null) {
    return _profilePage(
      context,
      name: submittedName,
      image: submittedImage,
      error: _friendlyAuthError(browserError),
      statusCode: HttpStatus.forbidden,
    );
  }
  if (!manager.validateCsrf(context, payload)) {
    return _profilePage(
      context,
      name: submittedName,
      image: submittedImage,
      error: _friendlyAuthError('invalid_csrf'),
      statusCode: HttpStatus.forbidden,
    );
  }

  final validationError = _profileValidationError(
    name: submittedName,
    image: submittedImage,
  );
  if (validationError != null) {
    return _profilePage(
      context,
      name: submittedName,
      image: submittedImage,
      error: validationError,
      statusCode: HttpStatus.badRequest,
    );
  }

  final session = await manager.resolveSession(context);
  if (session == null) return context.redirect('/login');
  final current = await manager.store.users.findById(session.user.id);
  if (current == null) return context.redirect('/login');

  final updated = AuthUser(
    id: current.id,
    email: current.email,
    name: submittedName.isEmpty ? null : submittedName,
    image: submittedImage.isEmpty ? null : submittedImage,
    roles: current.roles,
    isAnonymous: current.isAnonymous,
    attributes: current.attributes,
  );
  final stored = await manager.store.users.update(updated);
  if (stored == null) {
    return _profilePage(
      context,
      name: submittedName,
      image: submittedImage,
      error: 'We could not save your profile. Please try again.',
      statusCode: HttpStatus.badRequest,
    );
  }

  // Keep the browser cookie projection in sync with the durable user record.
  await manager.updateSession(context, stored.toSessionPrincipal());
  return context.redirect('/settings/profile?updated=1');
}

String? _profileValidationError({required String name, required String image}) {
  if (name.length > 80) return 'Display name must be 80 characters or fewer.';
  if (image.length > 2048) return 'Profile image URL is too long.';
  if (image.isEmpty) return null;
  final uri = Uri.tryParse(image);
  if (uri == null ||
      uri.host.isEmpty ||
      !{'http', 'https'}.contains(uri.scheme)) {
    return 'Profile image must be an HTTP or HTTPS URL.';
  }
  return null;
}

Future<Response> _sessionsPage(
  EngineContext context, {
  String? error,
  int statusCode = HttpStatus.ok,
}) async {
  final manager = _authManager(context);
  final session = await manager.resolveSession(context);
  if (session == null) return context.redirect('/login');
  final sessions = await manager.listSessions(context);
  final revoked = int.tryParse(
    context.request.queryParameters['revoked'] ?? '',
  );
  return _renderEmbeddedPage(context, 'sessions.liquid', <String, dynamic>{
    'csrf_token': manager.csrfToken(context),
    'sessions': sessions.map((value) => value.toJson()).toList(),
    'session_count': sessions.length,
    'revoked_notice': revoked == null ? null : _revokedSessionsMessage(revoked),
    'error': error,
  }, statusCode: statusCode);
}

String _revokedSessionsMessage(int count) {
  final suffix = count == 1 ? '' : 's';
  return 'Revoked $count other session$suffix.';
}

Future<Response> _revokeOtherSessions(EngineContext context) async {
  final manager = _authManager(context);
  final payload = await context.formCache;
  final browserError = manager.validateBrowserRequest(context);
  if (browserError != null || !manager.validateCsrf(context, payload)) {
    return await _sessionsPage(
      context,
      error: _friendlyAuthError(browserError ?? 'invalid_csrf'),
      statusCode: HttpStatus.forbidden,
    );
  }
  try {
    final revoked = await manager.revokeOtherSessions(context);
    return await context.redirect('/settings/sessions?revoked=$revoked');
  } on AuthFlowException {
    return _sessionsPage(
      context,
      error: 'We could not update your sessions. Please try again.',
      statusCode: HttpStatus.badRequest,
    );
  }
}

CredentialsProvider _credentialsProvider(AuthManager manager) {
  for (final provider in manager.runtime.providers) {
    if (provider is CredentialsProvider) return provider;
  }
  throw StateError('The example requires a credentials provider.');
}

List<AuthProvider> _cloudflareSocialProviders(
  CloudflareEnvironment environment,
  Uri origin,
) {
  final githubClientId = _optionalCloudflareTextBinding(
    environment,
    'GITHUB_CLIENT_ID',
  );
  final githubClientSecret = _optionalCloudflareTextBinding(
    environment,
    'GITHUB_CLIENT_SECRET',
  );

  final dropboxClientId = _optionalCloudflareTextBinding(
    environment,
    'DROPBOX_CLIENT_ID',
  );
  final dropboxClientSecret = _optionalCloudflareTextBinding(
    environment,
    'DROPBOX_CLIENT_SECRET',
  );

  final telegramBotToken = _optionalCloudflareTextBinding(
    environment,
    'TELEGRAM_BOT_TOKEN',
  );
  final telegramBotUsername = _optionalCloudflareTextBinding(
    environment,
    'TELEGRAM_BOT_USERNAME',
  );
  return socialProvidersFromValues(
    origin: origin,
    githubClientId: githubClientId,
    githubClientSecret: githubClientSecret,
    dropboxClientId: dropboxClientId,
    dropboxClientSecret: dropboxClientSecret,
    telegramBotToken: telegramBotToken,
    telegramBotUsername: telegramBotUsername,
  );
}

/// Builds the optional social providers from host-supplied secret values.
///
/// Cloudflare Workers use [_cloudflareSocialProviders] to read bindings,
/// while the Dart IO entrypoint can call this with [Platform.environment]
/// values. Keeping provider construction here ensures both hosts use the same
/// provider options, redirect paths, and profile models.
List<AuthProvider> socialProvidersFromValues({
  required Uri origin,
  String? githubClientId,
  String? githubClientSecret,
  String? dropboxClientId,
  String? dropboxClientSecret,
  String? telegramBotToken,
  String? telegramBotUsername,
}) {
  final providers = <AuthProvider>[];
  final baseOrigin = origin.toString().replaceFirst(RegExp(r'/$'), '');
  if (githubClientId != null && githubClientSecret != null) {
    providers.add(
      githubProvider(
        GitHubProviderOptions(
          clientId: githubClientId,
          clientSecret: githubClientSecret,
          redirectUri: '$baseOrigin/auth/callback/github',
        ),
      ),
    );
  }

  if (dropboxClientId != null && dropboxClientSecret != null) {
    providers.add(
      dropboxProvider(
        DropboxProviderOptions(
          clientId: dropboxClientId,
          clientSecret: dropboxClientSecret,
          redirectUri: '$baseOrigin/auth/callback/dropbox',
        ),
      ),
    );
  }

  if (telegramBotToken != null && telegramBotUsername != null) {
    providers.add(
      telegramProvider(
        TelegramProviderOptions(
          botToken: telegramBotToken,
          botUsername: telegramBotUsername,
          redirectUri: '$baseOrigin/auth/callback/telegram',
          successRedirect: '/dashboard',
        ),
      ),
    );
  }
  return providers;
}

String? _optionalCloudflareTextBinding(
  CloudflareEnvironment environment,
  String name,
) {
  try {
    final value = cloudflareTextBinding(environment, name).trim();
    return value.isEmpty ? null : value;
  } on Object {
    return null;
  }
}

Future<Response> _authPage(
  EngineContext context, {
  required bool login,
  String? error,
  String email = '',
  int statusCode = HttpStatus.ok,
}) {
  final manager = _authManager(context);
  return _renderEmbeddedPage(context, 'auth.liquid', <String, dynamic>{
    'title': login ? 'Welcome back.' : 'Make your first request.',
    'form_title': login ? 'Sign in' : 'Create your account',
    'form_copy': login
        ? 'Use your credentials to open the protected dashboard.'
        : 'Create a credential-backed account and see the session flow end to end.',
    'form_action': login ? '/login' : '/signup',
    'submit_label': login ? 'Sign in' : 'Create account',
    'password_autocomplete': login ? 'current-password' : 'new-password',
    'switch_copy': login ? 'Need an account?' : 'Already have an account?',
    'switch_label': login ? 'Create one' : 'Sign in',
    'switch_href': login ? '/signup' : '/login',
    'csrf_token': manager.csrfToken(context),
    'email': email,
    'error': error,
    'password_changed':
        context.request.queryParameters['password_changed'] == '1',
    'github_enabled': manager.runtime.providers.any(
      (provider) => provider.id == 'github',
    ),
    'dropbox_enabled': manager.runtime.providers.any(
      (provider) => provider.id == 'dropbox',
    ),
    'telegram_enabled': manager.runtime.providers.any(
      (provider) => provider.id == 'telegram',
    ),
    'telegram_bot_username': _providerValue<String>(
      manager,
      'telegram',
      (provider) => provider is TelegramProvider ? provider.botUsername : null,
    ),
    'telegram_redirect_uri': _providerValue<String>(
      manager,
      'telegram',
      (provider) => provider is TelegramProvider ? provider.redirectUri : null,
    ),
    'has_social_providers': manager.runtime.providers.any(
      (provider) =>
          provider.id == 'github' ||
          provider.id == 'dropbox' ||
          provider.id == 'telegram',
    ),
  }, statusCode: statusCode);
}

T? _providerValue<T>(
  AuthManager manager,
  String providerId,
  T? Function(AuthProvider provider) read,
) {
  for (final provider in manager.runtime.providers) {
    if (provider.id == providerId) return read(provider);
  }
  return null;
}

Future<Response> _credentialsForm(
  EngineContext context, {
  required bool login,
}) async {
  final manager = _authManager(context);
  final payload = await context.formCache;
  final email = payload['email']?.toString() ?? '';

  final browserError = manager.validateBrowserRequest(context);
  if (browserError != null) {
    return _authPage(
      context,
      login: login,
      email: email,
      error: _friendlyAuthError(browserError),
      statusCode: HttpStatus.forbidden,
    );
  }
  if (!manager.validateCsrf(context, payload)) {
    return _authPage(
      context,
      login: login,
      email: email,
      error: _friendlyAuthError('invalid_csrf'),
      statusCode: HttpStatus.forbidden,
    );
  }

  try {
    final credentials = AuthCredentials.fromMap(payload);
    final provider = _credentialsProvider(manager);
    if (login) {
      await manager.signInWithCredentials(context, provider, credentials);
    } else {
      await manager.registerWithCredentials(context, provider, credentials);
    }
    return await context.redirect('/dashboard');
  } on AuthFlowException catch (error) {
    return _authPage(
      context,
      login: login,
      email: email,
      error: _friendlyAuthError(error.code),
      statusCode: login && error.code == 'invalid_credentials'
          ? HttpStatus.unauthorized
          : HttpStatus.badRequest,
    );
  } catch (_) {
    // Do not expose storage, hashing, or provider details in a browser page.
    return _authPage(
      context,
      login: login,
      email: email,
      error: _friendlyAuthError('unknown'),
      statusCode: HttpStatus.badRequest,
    );
  }
}

Future<Response> _logout(EngineContext context) async {
  final manager = _authManager(context);
  final payload = await context.formCache;
  final browserError = manager.validateBrowserRequest(context);
  if (browserError != null || !manager.validateCsrf(context, payload)) {
    return context.redirect('/login');
  }

  await manager.signOut(context, destroyFrameworkSession: true);
  return context.redirect('/');
}

String _friendlyAuthError(String code) {
  switch (code) {
    case 'invalid_credentials':
      return 'That email or password is not correct.';
    case 'invalid_email':
      return 'Enter a valid email address.';
    case 'password_too_short':
      return 'Use at least 12 characters.';
    case 'password_too_long':
      return 'Choose a shorter password.';
    case 'invalid_current_password':
      return 'The current password is not correct.';
    case 'password_change_failed':
      return 'We could not change your password. Please try again.';
    case 'account_locked':
      return 'This account is temporarily locked. Try again later.';
    case 'account_disabled':
      return 'This account is currently unavailable.';
    case 'invalid_csrf':
      return 'This form expired. Refresh the page and try again.';
    case 'origin_not_allowed':
    case 'origin_missing':
      return 'The request origin was not accepted.';
    default:
      return 'We could not complete that request. Please try again.';
  }
}
