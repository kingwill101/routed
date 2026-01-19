import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:routed/routed.dart';

/// Telegram user profile returned by the Login Widget.
///
/// See [Telegram Login Widget](https://core.telegram.org/widgets/login).
class TelegramProfile {
  const TelegramProfile({
    required this.id,
    required this.authDate,
    this.firstName,
    this.lastName,
    this.username,
    this.photoUrl,
    this.hash,
  });

  /// Unique identifier for the user.
  final int id;

  /// Unix timestamp when the authentication was received.
  final int authDate;

  /// User's first name.
  final String? firstName;

  /// User's last name.
  final String? lastName;

  /// User's Telegram username.
  final String? username;

  /// URL of the user's profile photo.
  final String? photoUrl;

  /// HMAC-SHA-256 hash for verification.
  final String? hash;

  /// Returns the user's full name.
  String? get fullName {
    if (firstName == null && lastName == null) return null;
    return [firstName, lastName].whereType<String>().join(' ').trim();
  }

  factory TelegramProfile.fromJson(Map<String, dynamic> json) {
    return TelegramProfile(
      id: _parseInt(json['id']) ?? 0,
      authDate: _parseInt(json['auth_date']) ?? 0,
      firstName: json['first_name']?.toString(),
      lastName: json['last_name']?.toString(),
      username: json['username']?.toString(),
      photoUrl: json['photo_url']?.toString(),
      hash: json['hash']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'auth_date': authDate,
        'first_name': firstName,
        'last_name': lastName,
        'username': username,
        'photo_url': photoUrl,
        'hash': hash,
      };

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// Configuration for the Telegram Login Widget provider.
///
/// ### Setup
///
/// 1. Create a bot via [@BotFather](https://t.me/botfather)
/// 2. Use `/setdomain` to link your website's domain to the bot
/// 3. Embed the Telegram Login Widget on your page
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/telegram
/// ```
///
/// ### Widget Example
/// ```html
/// <script async src="https://telegram.org/js/telegram-widget.js?22"
///   data-telegram-login="YOUR_BOT_USERNAME"
///   data-size="large"
///   data-auth-url="https://example.com/auth/callback/telegram"
///   data-request-access="write">
/// </script>
/// ```
///
/// ### Usage
/// ```dart
/// import 'package:routed/auth.dart';
/// import 'package:routed_auth/routed_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
///     providers: [
///       telegramProvider(
///         TelegramProviderOptions(
///           botToken: env('TELEGRAM_BOT_TOKEN'),
///           botUsername: env('TELEGRAM_BOT_USERNAME'),
///           redirectUri: 'https://example.com/auth/callback/telegram',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// ### Notes
///
/// - Telegram uses a widget-based flow, not standard OAuth.
/// - The bot token is used to verify the HMAC-SHA-256 hash.
/// - Set [authDateMaxAge] to reject stale authentications.
class TelegramProviderOptions {
  const TelegramProviderOptions({
    required this.botToken,
    required this.botUsername,
    required this.redirectUri,
    this.authDateMaxAge = const Duration(minutes: 5),
    this.successRedirect = '/profile',
  });

  /// Bot token from @BotFather (used for HMAC verification).
  final String botToken;

  /// Bot username (without @).
  final String botUsername;

  /// Redirect URI for the callback.
  final String redirectUri;

  /// Maximum age of auth_date before rejecting (default: 5 minutes).
  final Duration authDateMaxAge;

  /// Where to redirect after successful authentication.
  final String successRedirect;
}

/// Telegram Login Widget provider.
///
/// This is a custom auth provider since Telegram doesn't use standard OAuth.
/// It uses HMAC-SHA-256 verification with the bot token.
///
/// ### Resources
/// - https://core.telegram.org/widgets/login
/// - https://core.telegram.org/bots#botfather
class TelegramProvider extends AuthProvider with CallbackProvider {
  TelegramProvider({
    required this.botToken,
    required this.botUsername,
    required this.redirectUri,
    required this.profile,
    this.authDateMaxAge = const Duration(minutes: 5),
    this.successRedirect = '/profile',
  }) : super(
          id: 'telegram',
          name: 'Telegram',
          type: AuthProviderType.oauth, // Closest match
        );

  /// Bot token from @BotFather.
  final String botToken;

  /// Bot username (without @).
  final String botUsername;

  /// Redirect URI for the callback.
  final String redirectUri;

  /// Maximum age of auth_date before rejecting.
  final Duration authDateMaxAge;

  /// Where to redirect after successful authentication.
  final String successRedirect;

  /// Maps the Telegram profile to an AuthUser.
  final AuthUser Function(TelegramProfile profile) profile;

  /// Generates the authorization URL (widget page).
  ///
  /// Note: Unlike OAuth, Telegram requires embedding a widget on your page.
  /// This URL can be used as a reference or for custom implementations.
  Uri getAuthorizationUrl() {
    // Telegram widget is typically embedded, but we can provide a URL
    // that shows where to redirect after auth
    return Uri.parse(
      'https://oauth.telegram.org/auth?bot_id=${_extractBotId()}&origin=${Uri.encodeComponent(redirectUri)}&request_access=write',
    );
  }

  String _extractBotId() {
    // Bot token format: <bot_id>:<secret>
    final parts = botToken.split(':');
    return parts.isNotEmpty ? parts.first : '';
  }

  /// Handles the callback from Telegram Login Widget.
  ///
  /// This is called automatically by AuthRoutes when the callback URL is
  /// accessed. It verifies the HMAC signature and returns the user.
  @override
  Future<CallbackResult> handleCallback(
    EngineContext ctx,
    Map<String, String> params,
  ) async {
    try {
      final telegramProfile = verifyAndParseCallback(params);
      final user = mapProfile(telegramProfile);
      return CallbackResult.success(user, redirect: successRedirect);
    } on TelegramAuthException catch (e) {
      return CallbackResult.failure(e.message);
    }
  }

  /// Verifies the authentication data from Telegram.
  ///
  /// Returns the parsed profile if valid, throws if invalid.
  TelegramProfile verifyAndParseCallback(Map<String, String> params) {
    final hash = params['hash'];
    if (hash == null || hash.isEmpty) {
      throw TelegramAuthException('Missing hash parameter');
    }

    // Build data-check-string (sorted alphabetically, excluding hash)
    final dataCheckParts = <String>[];
    final sortedKeys = params.keys.where((k) => k != 'hash').toList()..sort();
    for (final key in sortedKeys) {
      final value = params[key];
      if (value != null && value.isNotEmpty) {
        dataCheckParts.add('$key=$value');
      }
    }
    final dataCheckString = dataCheckParts.join('\n');

    // Calculate expected hash
    // secret_key = SHA256(bot_token)
    // hash = HMAC_SHA256(data_check_string, secret_key)
    final secretKey = sha256.convert(utf8.encode(botToken)).bytes;
    final hmac = Hmac(sha256, secretKey);
    final expectedHash = hmac.convert(utf8.encode(dataCheckString)).toString();

    if (hash != expectedHash) {
      throw TelegramAuthException('Invalid hash - authentication failed');
    }

    // Check auth_date freshness
    final authDateStr = params['auth_date'];
    if (authDateStr != null) {
      final authDate = int.tryParse(authDateStr);
      if (authDate != null) {
        final authTime = DateTime.fromMillisecondsSinceEpoch(authDate * 1000);
        final now = DateTime.now();
        if (now.difference(authTime) > authDateMaxAge) {
          throw TelegramAuthException(
            'Authentication expired - auth_date too old',
          );
        }
      }
    }

    return TelegramProfile.fromJson(
      params.map((k, v) => MapEntry(k, v)),
    );
  }

  /// Maps the verified profile to an AuthUser.
  AuthUser mapProfile(TelegramProfile telegramProfile) {
    return profile(telegramProfile);
  }
}

/// Exception thrown when Telegram authentication fails.
class TelegramAuthException implements Exception {
  TelegramAuthException(this.message);
  final String message;

  @override
  String toString() => 'TelegramAuthException: $message';
}

/// Creates a Telegram Login Widget provider.
///
/// ### Resources
/// - https://core.telegram.org/widgets/login
TelegramProvider telegramProvider(TelegramProviderOptions options) {
  return TelegramProvider(
    botToken: options.botToken,
    botUsername: options.botUsername,
    redirectUri: options.redirectUri,
    authDateMaxAge: options.authDateMaxAge,
    successRedirect: options.successRedirect,
    profile: (profile) {
      return AuthUser(
        id: profile.id.toString(),
        name: profile.fullName,
        email: null, // Telegram doesn't provide email
        image: profile.photoUrl,
        attributes: profile.toJson(),
      );
    },
  );
}

const Duration _defaultAuthDateMaxAge = Duration(minutes: 5);

AuthProviderRegistration _telegramRegistration() {
  return AuthProviderRegistration(
    id: 'telegram',
    schema: ConfigSchema.object(
      description: 'Telegram Login Widget provider settings.',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the Telegram provider.',
          defaultValue: false,
        ),
        'bot_token': ConfigSchema.string(
          description: 'Telegram bot token from @BotFather.',
          defaultValue: "{{ env.TELEGRAM_BOT_TOKEN | default: '' }}",
        ),
        'bot_username': ConfigSchema.string(
          description: 'Telegram bot username (without @).',
          defaultValue: "{{ env.TELEGRAM_BOT_USERNAME | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'Redirect URI for Telegram callbacks.',
          defaultValue: "{{ env.TELEGRAM_REDIRECT_URI | default: '' }}",
        ),
        'auth_date_max_age_seconds': ConfigSchema.integer(
          description: 'Maximum age of auth_date in seconds (default: 300).',
          defaultValue: 300,
        ),
      },
    ),
    builder: _buildTelegramProvider,
  );
}

AuthProvider? _buildTelegramProvider(Map<String, dynamic> config) {
  final enabled = parseBoolLike(
        config['enabled'],
        context: 'auth.providers.telegram.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final botToken = _requireString(
    config['bot_token'],
    'auth.providers.telegram.bot_token',
  );
  final botUsername = _requireString(
    config['bot_username'],
    'auth.providers.telegram.bot_username',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.telegram.redirect_uri',
  );
  final maxAgeSeconds = config['auth_date_max_age_seconds'] as int? ?? 300;

  return telegramProvider(
    TelegramProviderOptions(
      botToken: botToken,
      botUsername: botUsername,
      redirectUri: redirectUri,
      authDateMaxAge: maxAgeSeconds > 0
          ? Duration(seconds: maxAgeSeconds)
          : _defaultAuthDateMaxAge,
    ),
  );
}

String _requireString(Object? value, String context) {
  final resolved = parseStringLike(
    value,
    context: context,
    allowEmpty: true,
    throwOnInvalid: true,
  );
  if (resolved == null || resolved.trim().isEmpty) {
    throw ProviderConfigException('$context is required');
  }
  return resolved.trim();
}

/// Register the Telegram Login Widget provider with the registry.
void registerTelegramAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(
    _telegramRegistration(),
    overrideExisting: overrideExisting,
  );
}
