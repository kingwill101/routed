import 'dart:io';

import 'package:routed/auth/providers/github.dart';
import 'package:routed/routed.dart';

Future<void> _registerAuthEvents(Engine engine) async {
  final eventManager = await engine.container.make<EventManager>();
  eventManager.listen<Event>((event) {
    switch (event) {
      case AuthCreateUserEvent createUserEvent:
        stdout.writeln('Auth user created: ${createUserEvent.user.id}');
      case AuthUpdateUserEvent updateUserEvent:
        stdout.writeln('Auth user updated: ${updateUserEvent.user.id}');
      case AuthLinkAccountEvent linkAccountEvent:
        stdout.writeln(
          'Auth account linked: ${linkAccountEvent.account.providerId}',
        );
      default:
        break;
    }
  });
}

Future<Engine> createJwtEngine() async {
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
            sessionStrategy: AuthSessionStrategy.jwt,
            jwtOptions: const JwtSessionOptions(secret: 'dev-secret'),
            callbacks: AuthCallbacks(
              jwt: (context) async {
                return {...context.token, 'role': 'member'};
              },
              session: (context) async {
                return {...context.payload, 'jwt': true};
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
      'message': 'Welcome to Auth JWT Demo!',
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
