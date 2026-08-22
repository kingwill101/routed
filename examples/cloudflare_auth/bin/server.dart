import 'dart:io';

import 'package:routed/routed.dart';
import 'package:routed_cloudflare_auth_example/app.dart' as app;

const _localSessionKey =
    'base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==';

Future<void> main() async {
  final host = Platform.environment['HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final origin = Uri.parse(
    Platform.environment['AUTH_ORIGIN'] ?? 'http://$host:$port',
  );
  String? environmentValue(String name) {
    final value = Platform.environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  final engine = await app.createEngine(
    store: InMemoryAuthStore(),
    origin: origin,
    sessionKey: Platform.environment['SESSION_KEY'] ?? _localSessionKey,
    localDevelopment: true,
    socialProviders: app.socialProvidersFromValues(
      origin: origin,
      githubClientId: environmentValue('GITHUB_CLIENT_ID'),
      githubClientSecret: environmentValue('GITHUB_CLIENT_SECRET'),
      dropboxClientId: environmentValue('DROPBOX_CLIENT_ID'),
      dropboxClientSecret: environmentValue('DROPBOX_CLIENT_SECRET'),
      telegramBotToken: environmentValue('TELEGRAM_BOT_TOKEN'),
      telegramBotUsername: environmentValue('TELEGRAM_BOT_USERNAME'),
    ),
  );
  await engine.serve(host: host, port: port);
}
