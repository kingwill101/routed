/// Telegram Login Widget Authentication Example
///
/// This example demonstrates how to integrate Telegram Login Widget
/// authentication with routed using the TelegramProvider from routed_auth.
///
/// ## Setup
///
/// 1. Create a bot via [@BotFather](https://t.me/botfather)
/// 2. Use `/setdomain` command to link your domain to the bot
/// 3. Set environment variables:
///    - TELEGRAM_BOT_TOKEN: Your bot token from BotFather
///    - TELEGRAM_BOT_USERNAME: Your bot username (without @)
///
/// ## How It Works
///
/// Unlike traditional OAuth, Telegram uses a widget-based flow:
/// 1. User clicks the Telegram Login Widget on your page
/// 2. Telegram authenticates the user and redirects to your callback URL
/// 3. Your server verifies the HMAC-SHA-256 hash using your bot token
/// 4. On success, create a session for the user
///
/// ## Run
///
/// ```bash
/// export TELEGRAM_BOT_TOKEN="your-bot-token"
/// export TELEGRAM_BOT_USERNAME="your-bot-username"
/// dart run examples/telegram_auth.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed/session.dart';
import 'package:routed/src/sessions/middleware.dart';
import 'package:routed_auth/routed_auth.dart';

void main() async {
  // Get credentials from environment
  final botToken = Platform.environment['TELEGRAM_BOT_TOKEN'] ?? "";
  final botUsername = Platform.environment['TELEGRAM_BOT_USERNAME'] ?? "";
  final baseUrl = Platform.environment['BASE_URL'] ?? "";

  print('🤖 Telegram Auth Example');
  print('   Bot Username: @$botUsername');
  print('   Base URL: $baseUrl');
  print('');

  // Configure session
  final sessionConfig = SessionConfig.cookie(
    appKey: 'base64:${base64.encode(List<int>.generate(32, (i) => i + 1))}',
    cookieName: 'telegram_session',
    options: Options(
      path: '/',
      secure: true, // HTTPS via Tailscale
      httpOnly: true,
      sameSite: SameSite.lax,
    ),
  );

  // Create Telegram provider - seamlessly integrates with AuthRoutes!
  // The TelegramProvider implements CallbackProvider, so AuthRoutes
  // automatically handles /auth/callback/telegram
  final telegram = telegramProvider(
    TelegramProviderOptions(
      botToken: botToken,
      botUsername: botUsername,
      redirectUri: '$baseUrl/auth/callback/telegram',
      authDateMaxAge: const Duration(minutes: 5),
      successRedirect: '/profile', // Where to redirect after auth
    ),
  );

  // Create auth manager
  final authManager = AuthManager(
    AuthOptions(
      providers: [telegram],
      sessionStrategy: AuthSessionStrategy.session,
      enforceCsrf: false, // Telegram widget doesn't support CSRF tokens
      callbacks: AuthCallbacks(
        signIn: (context) async {
          print('✅ User signed in: ${context.user.name} (${context.user.id})');
          return const AuthSignInResult.allow();
        },
      ),
    ),
  );

  // Create engine
  final engine = Engine(
    config: EngineConfig(
      security: const EngineSecurityFeatures(csrfProtection: false),
    ),
    providers: Engine.defaultProviders,
    options: [withSessionConfig(sessionConfig)],
  );

  // Add middleware
  engine.addGlobalMiddleware(
    sessionMiddleware(
      store: sessionConfig.store,
      name: sessionConfig.cookieName,
    ),
  );
  engine.addGlobalMiddleware(SessionAuth.sessionAuthMiddleware());

  // Register auth routes - handles /auth/callback/telegram automatically!
  // The TelegramProvider implements CallbackProvider mixin, so AuthRoutes
  // verifies the HMAC signature and creates the session seamlessly.
  AuthRoutes(authManager).register(engine.defaultRouter);

  // Home page with Telegram Login Widget
  engine.get('/', (ctx) {
    return ctx.html('''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Telegram Auth Demo</title>
  <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gradient-to-br from-blue-500 to-purple-600 min-h-screen flex items-center justify-center">
  <div class="bg-white rounded-lg shadow-lg p-8 max-w-md w-full">
    <h1 class="text-2xl font-bold text-gray-800 mb-4">🤖 Telegram Login</h1>
    <p class="text-gray-600 mb-6">
      Sign in with your Telegram account using the secure Telegram Login Widget.
      Your data is verified using HMAC-SHA-256 cryptographic signatures.
    </p>

    <div class="flex justify-center mb-6">
      <!-- Telegram Login Widget -->
      <script async src="https://telegram.org/js/telegram-widget.js?22"
        data-telegram-login="$botUsername"
        data-size="large"
        data-radius="8"
        data-auth-url="$baseUrl/auth/callback/telegram"
        data-request-access="write">
      </script>
    </div>

    <div class="bg-yellow-100 border border-yellow-400 text-yellow-800 rounded-lg p-4 text-sm">
      <strong>⚠️ Demo Mode:</strong> This example uses a demo bot token.
      For production, create your own bot via
      <a href="https://t.me/botfather" target="_blank" class="text-blue-500 underline">@BotFather</a>
      and set the <code class="bg-gray-100 px-1 rounded">TELEGRAM_BOT_TOKEN</code> environment variable.
    </div>

    <div class="mt-6 border-t pt-4">
      <a href="/profile" class="text-blue-500 hover:underline mr-4">View Profile</a>
      <a href="/auth/providers" class="text-blue-500 hover:underline mr-4">Auth Providers</a>
      <a href="/auth/session" class="text-blue-500 hover:underline">Session Info</a>
    </div>
  </div>
</body>
</html>
''');
  });

  // Protected profile page
  engine.get('/profile', (ctx) async {
    // Check if user is authenticated using SessionAuth
    final principal = SessionAuth.current(ctx);

    if (principal == null) {
      return ctx.html('''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Profile - Not Authenticated</title>
  <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100 min-h-screen flex items-center justify-center">
  <div class="text-center">
    <div class="bg-red-100 border border-red-400 text-red-800 rounded-lg p-6 mb-4">
      <h2 class="text-xl font-bold">🔒 Not Authenticated</h2>
      <p class="mt-2">Please sign in with Telegram to view your profile.</p>
    </div>
    <a href="/" class="text-blue-500 hover:underline">← Back to Login</a>
  </div>
</body>
</html>
''');
    }

    // Get user info from the principal's attributes
    final attrs = principal.attributes;
    final name = attrs['name']?.toString() ?? principal.id;
    final photoUrl = attrs['image']?.toString();

    return ctx.html('''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Profile - $name</title>
  <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100 min-h-screen flex items-center justify-center">
  <div class="bg-white rounded-lg shadow-lg p-8 max-w-md w-full">
    ${photoUrl != null ? '<img src="$photoUrl" class="w-24 h-24 rounded-full mx-auto mb-4" alt="Avatar">' : '<div class="w-24 h-24 rounded-full bg-blue-500 mx-auto mb-4 flex items-center justify-center text-white text-3xl">👤</div>'}

    <h1 class="text-2xl font-bold text-center text-gray-800 mb-6">Welcome, $name!</h1>

    <div class="bg-gray-50 rounded-lg p-4 mb-6">
      <div class="flex justify-between py-2 border-b">
        <span class="text-gray-600">Telegram ID</span>
        <span class="text-gray-800 font-medium">${principal.id}</span>
      </div>
      <div class="flex justify-between py-2 border-b">
        <span class="text-gray-600">Name</span>
        <span class="text-gray-800 font-medium">$name</span>
      </div>
      ${attrs['username'] != null ? '''
      <div class="flex justify-between py-2 border-b">
        <span class="text-gray-600">Username</span>
        <span class="text-gray-800 font-medium">@${attrs['username']}</span>
      </div>
      ''' : ''}
      ${attrs['auth_date'] != null ? '''
      <div class="flex justify-between py-2">
        <span class="text-gray-600">Auth Date</span>
        <span class="text-gray-800 font-medium">${_formatAuthDate(attrs['auth_date'])}</span>
      </div>
      ''' : ''}
    </div>

    <div class="text-center">
      <a href="/" class="bg-gray-500 text-white px-4 py-2 rounded-lg mr-2">← Home</a>
      <a href="/logout" class="bg-red-500 text-white px-4 py-2 rounded-lg">Sign Out</a>
    </div>
  </div>
</body>
</html>
''');
  });

  // Logout endpoint
  engine.get('/logout', (ctx) async {
    await SessionAuth.logout(ctx);
    ctx.destroySession();
    return ctx.redirect('/');
  });

  await engine.initialize();

  print('');
  print('🚀 Server running at $baseUrl');
  print('');
  print('📝 Available routes:');
  print('   GET  /                      - Home page with Telegram widget');
  print('   GET  /profile               - Protected profile page');
  print('   GET  /logout                - Sign out');
  print(
    '   GET  /auth/callback/telegram - Telegram callback (handled by AuthRoutes)',
  );
  print('   GET  /auth/session          - Current session info');
  print('   GET  /auth/providers        - List auth providers');
  print('');
  print('⚠️  Note: For the widget to work, you need to:');
  print('   1. Create a bot via @BotFather');
  print('   2. Use /setdomain to link your domain');
  print('   3. Set TELEGRAM_BOT_TOKEN and TELEGRAM_BOT_USERNAME env vars');
  print('');

  // Use '0.0.0.0' to bind to all interfaces (both IPv4 and IPv6)
  // Using 'localhost' only binds to IPv6 (::1) on many systems
  await engine.serve(host: '0.0.0.0', port: 8081);
}

String _formatAuthDate(dynamic authDate) {
  if (authDate == null) return 'Unknown';
  final timestamp = authDate is int
      ? authDate
      : int.tryParse(authDate.toString());
  if (timestamp == null) return 'Unknown';
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
