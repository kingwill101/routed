/// Example: Google OAuth with routed_auth.
///
/// This demonstrates how to configure the Google OAuth provider
/// and wire up the login and callback routes using the routed framework.
///
/// Before running, set the following environment variables:
/// ```sh
/// export GOOGLE_CLIENT_ID=your-client-id
/// export GOOGLE_CLIENT_SECRET=your-client-secret
/// ```
///
/// Then run:
/// ```sh
/// dart run example/oauth_example.dart
/// ```
library;

import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_auth/routed_auth.dart';

Future<void> main() async {
  // 1. Build the Google OAuth provider.
  final google = googleProvider(
    GoogleProviderOptions(
      clientId: Platform.environment['GOOGLE_CLIENT_ID'] ?? '',
      clientSecret: Platform.environment['GOOGLE_CLIENT_SECRET'] ?? '',
      redirectUri: 'http://localhost:3000/auth/callback/google',
      accessType: 'offline',
      prompt: 'consent',
    ),
  );

  // 2. Create the engine with AuthServiceProvider.
  //    AuthOptions is registered in the container so that
  //    AuthServiceProvider can build the AuthManager automatically.
  final engine = await Engine.create(
    providers: [...Engine.defaultProviders, AuthServiceProvider()],
  );

  engine.container.instance<AuthOptions>(AuthOptions(providers: [google]));

  // 3. Redirect the user to Google's consent screen.
  engine.get('/auth/google', (EngineContext ctx) async {
    final manager = ctx.container.get<AuthManager>();
    final provider =
        manager.resolveProvider('google')! as OAuthProvider<GoogleProfile>;
    final authUrl = await manager.beginOAuth(ctx, provider);
    ctx.redirect(authUrl.toString());
  });

  // 4. Handle the OAuth callback from Google.
  engine.get('/auth/callback/google', (EngineContext ctx) async {
    final manager = ctx.container.get<AuthManager>();
    final provider =
        manager.resolveProvider('google')! as OAuthProvider<GoogleProfile>;

    final code = ctx.query('code') ?? '';
    final state = ctx.query('state');
    final result = await manager.finishOAuth(ctx, provider, code, state);

    ctx.json({
      'user': result.user.name,
      'email': result.user.email,
      'image': result.user.image,
    });
  });

  // 5. Home page with a sign-in link.
  engine.get('/', (EngineContext ctx) {
    ctx.html('<a href="/auth/google">Sign in with Google</a>');
  });

  await engine.serve(port: 3000);
  print('Listening on http://localhost:3000');
}
