import 'dart:io';

import 'package:routed/auth/providers/github.dart';
import 'package:routed/routed.dart';

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
          ),
        );
      },
    ],
  );

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
