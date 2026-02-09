import 'dart:io';

import 'package:routed/auth/providers/github.dart';
import 'package:routed/routed.dart';

Future<void> _registerAuthEvents(Engine engine) async {
  final eventManager = await engine.container.make<EventManager>();
  eventManager.listen<Event>((event) {
    switch (event) {
      case AuthSignInEvent signInEvent:
        stdout.writeln('Sign-in: ${signInEvent.user.id}');
      case AuthSignOutEvent signOutEvent:
        stdout.writeln('Sign-out: ${signOutEvent.user?.id}');
      case AuthSessionEvent sessionEvent:
        stdout.writeln('Session: ${sessionEvent.session.user.id}');
      default:
        break;
    }
  });
}

Future<Engine> createEngine() async {
  final engine = await Engine.create(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: Engine.defaultProviders,
    options: [
      (engine) {
        final providers = <AuthProvider>[
          CredentialsProvider(),
          EmailProvider(
            sendVerificationRequest: (ctx, provider, request) async {
              final callbackUrl = request.callbackUrl.isEmpty
                  ? 'http://localhost:8080/auth/callback/email'
                  : request.callbackUrl;
              final link =
                  '$callbackUrl?token=${request.token}&email=${request.email}';
              stdout.writeln('Magic link: $link');
            },
          ),
        ];

        final githubClientId = Platform.environment['GITHUB_CLIENT_ID'];
        final githubClientSecret = Platform.environment['GITHUB_CLIENT_SECRET'];
        final githubRedirect =
            Platform.environment['GITHUB_REDIRECT_URI'] ??
            'http://localhost:8080/auth/callback/github';
        if (githubClientId != null && githubClientSecret != null) {
          providers.add(
            githubProvider(
              GitHubProviderOptions(
                clientId: githubClientId,
                clientSecret: githubClientSecret,
                redirectUri: githubRedirect,
              ),
            ),
          );
        }

        engine.container.instance<AuthOptions>(
          AuthOptions(
            providers: providers,
            adapter: InMemoryAuthAdapter(),
            sessionStrategy: AuthSessionStrategy.session,
            callbacks: AuthCallbacks(
              signIn: (context) async {
                if (context.user.email == null) {
                  return const AuthSignInResult.deny();
                }
                return const AuthSignInResult.allow();
              },
              redirect: (context) async {
                return context.url;
              },
              session: (context) async {
                return {...context.payload, 'demo': true};
              },
            ),
          ),
        );
      },
    ],
  );

  await _registerAuthEvents(engine);

  engine.get('/', (ctx) async {
    return ctx.json({
      'message': 'Welcome to Auth Demo!',
      'routes': {
        'providers': '/auth/providers',
        'csrf': '/auth/csrf',
        'signin': '/auth/signin/{provider}',
        'register': '/auth/register/credentials',
        'callback': '/auth/callback/{provider}',
        'session': '/auth/session',
        'signout': '/auth/signout',
        'update_profile': '/update-profile',
      },
    });
  });

  // ── Example: updating the current session after a profile change ──
  //
  // SessionAuth.updateSession() is the recommended way to refresh the
  // session (or reissue the JWT) after modifying user attributes.
  // It delegates to AuthManager when available, handling both session
  // and JWT strategies transparently — no container lookup needed.
  engine.post('/update-profile', (ctx) async {
    final principal = SessionAuth.current(ctx);
    if (principal == null) {
      return ctx.json({
        'error': 'not_authenticated',
      }, statusCode: HttpStatus.unauthorized);
    }

    final form = await ctx.formCache;
    final newName = form['name']?.toString().trim();
    final newTheme = form['theme']?.toString().trim();

    // Build an updated principal with the changed attributes.
    final updated = AuthPrincipal(
      id: principal.id,
      roles: principal.roles,
      attributes: {
        ...principal.attributes,
        if (newName != null && newName.isNotEmpty) 'name': newName,
        if (newTheme != null && newTheme.isNotEmpty) 'theme': newTheme,
      },
    );

    // Single call — works for both session and JWT strategies.
    await SessionAuth.updateSession(ctx, updated);

    return ctx.json({
      'message': 'Profile updated',
      'principal': updated.toJson(),
    });
  });

  return engine;
}
