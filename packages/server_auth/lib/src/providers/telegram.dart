import 'dart:convert';

import 'package:crypto/crypto.dart';
import '../core/core.dart';

/// Telegram user profile returned by the Login Widget.
///
/// See [Telegram Login Widget](https://core.telegram.org/widgets/login).
class TelegramProfile {
  /// Creates a new [TelegramProfile] with the given fields.
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

  /// Creates a [TelegramProfile] from a JSON map received via the Telegram Login Widget callback.
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

  /// Converts this profile to a JSON-serializable map.
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
/// import 'package:server_auth/server_auth.dart';
/// import 'package:server_auth/server_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
///     store: InMemoryAuthStore(),
///     storeMode: AuthStoreMode.ephemeral,
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
  /// Creates a new [TelegramProviderOptions] configuration.
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
  /// Creates a new [TelegramProvider] with the given options.
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
    AuthContext ctx,
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

    if (!constantTimeStringEquals(hash, expectedHash)) {
      throw TelegramAuthException('Invalid hash - authentication failed');
    }

    // Check auth_date freshness
    final authDateStr = params['auth_date'];
    final authDate = int.tryParse(authDateStr ?? '');
    if (authDate == null || authDate <= 0) {
      throw TelegramAuthException('Invalid auth_date');
    }
    late final DateTime authTime;
    try {
      authTime = DateTime.fromMillisecondsSinceEpoch(
        authDate * 1000,
        isUtc: true,
      );
    } on ArgumentError {
      throw TelegramAuthException('Invalid auth_date');
    }
    final now = DateTime.now().toUtc();
    final age = now.difference(authTime);
    if (age > authDateMaxAge || age < -const Duration(minutes: 1)) {
      throw TelegramAuthException('Authentication timestamp is invalid');
    }

    final id = int.tryParse(params['id'] ?? '');
    if (id == null || id <= 0) {
      throw TelegramAuthException('Invalid Telegram user id');
    }

    return TelegramProfile.fromJson(params.map((k, v) => MapEntry(k, v)));
  }

  /// Maps the verified profile to an AuthUser.
  AuthUser mapProfile(TelegramProfile telegramProfile) {
    return profile(telegramProfile);
  }
}

/// Exception thrown when Telegram authentication fails.
class TelegramAuthException implements Exception {
  /// Creates a new [TelegramAuthException] with the given [message].
  TelegramAuthException(this.message);

  /// Human-readable description of the authentication failure.
  final String message;

  /// Returns a string representation of this exception.
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
