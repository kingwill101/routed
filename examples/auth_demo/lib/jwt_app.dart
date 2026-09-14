import 'dart:io';

import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed/routed.dart';
import 'package:routed_database/routed_database.dart' hide Event;
import 'package:server_auth_ormed/server_auth_ormed.dart';

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

Future<Engine> createJwtEngine({
  String databasePath = 'storage/auth_demo_jwt.sqlite',
}) async {
  registerRoutedProviders();
  if (databasePath != ':memory:') {
    File(databasePath).absolute.parent.createSync(recursive: true);
  }
  final database = await SqliteDatabase.connect(path: databasePath);
  final schema = const OrmAuthSchema(tablePrefix: 'auth_demo_jwt');
  final store = OrmAuthStore(database, schema: schema);
  final databases = DatabaseManager()..register('default', database);
  final engine = await Engine.create(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: [
      RoutedDatabaseProvider(
        manager: databases,
        migrations: schema.migrations,
        migrateOnBoot: true,
      ),
      ...Engine.defaultProviders,
    ],
    options: [
      (engine) {
        final providers = <AuthProvider>[CredentialsProvider()];
        final magicLink = MagicLinkPlugin<EngineContext>(
          sendMagicLink: (delivery) async {
            final callbackUrl = delivery.callbackUrl.isEmpty
                ? 'http://localhost:8080/auth/callback/email'
                : delivery.callbackUrl;
            final link =
                '$callbackUrl?token=${delivery.token}&email=${delivery.email}';
            stdout.writeln('Magic link: $link');
          },
        );

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
            plugins: [magicLink],
            store: store,
            storeMode: AuthStoreMode.durable,
            runtimeMode: AuthRuntimeMode.localDevelopment,
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
