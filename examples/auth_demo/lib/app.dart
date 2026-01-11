import 'dart:io';

import 'package:routed/auth/providers/github.dart';
import 'package:routed/routed.dart';

Future<void> _registerAuthEvents(Engine engine) async {
  final eventManager = await engine.container.make<EventManager>();
  eventManager.listen<Event>((event) {
    if (event is AuthSignInEvent) {
      final signInEvent = event as AuthSignInEvent;
      stdout.writeln('Sign-in: ${signInEvent.user.id}');
    }
    if (event is AuthSignOutEvent) {
      final signOutEvent = event as AuthSignOutEvent;
      stdout.writeln('Sign-out: ${signOutEvent.user?.id}');
    }
    if (event is AuthSessionEvent) {
      final sessionEvent = event as AuthSessionEvent;
      stdout.writeln('Session: ${sessionEvent.session.user.id}');
    }
  });
}

Future<Engine> createEngine() async {
  final engine = await Engine.create(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
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
      },
    });
  });

  return engine;
}
