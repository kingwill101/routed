import 'dart:io';

import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed/routed.dart';
import 'package:routed_auth_sqlite/routed_auth_sqlite.dart';
import 'package:server_auth_ormed/server_auth_ormed.dart';
import 'package:routed_cloudflare_auth_example/app.dart' as app;

const _localSessionKey =
    'base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==';

Future<void> main() async {
  final host = Platform.environment['HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final origin = Uri.parse(
    Platform.environment['AUTH_ORIGIN'] ?? 'http://$host:$port',
  );
  final databasePath =
      Platform.environment['AUTH_DATABASE_PATH'] ??
      'storage/cloudflare_auth.sqlite';
  File(databasePath).absolute.parent.createSync(recursive: true);
  final database = await SqliteDatabase.connect(path: databasePath);
  final store = await OrmAuthStore.open(database);
  // OrmAuthStore owns core user/session data. API keys use a second durable
  // SQLite adapter until server_auth_ormed exposes the API-key capability.
  final apiKeyStore = await SqliteAuthStore.openPath('$databasePath.api-keys');
  String? environmentValue(String name) {
    final value = Platform.environment[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  final engine = await app.createEngine(
    store: store,
    apiKeyStore: apiKeyStore.apiKeys,
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
  try {
    await engine.serve(host: host, port: port);
  } finally {
    apiKeyStore.close();
    await database.close();
  }
}
