import 'package:routed/routed.dart';

/// Twitch user profile (OIDC).
///
/// See [Twitch OIDC](https://dev.twitch.tv/docs/authentication/getting-tokens-oidc/).
class TwitchProfile {
  const TwitchProfile({
    required this.sub,
    this.email,
    this.emailVerified,
    this.preferredUsername,
    this.picture,
    this.updatedAt,
  });

  /// Subject identifier (user ID).
  final String sub;

  /// User's email address.
  final String? email;

  /// Whether the email has been verified.
  final bool? emailVerified;

  /// User's display name.
  final String? preferredUsername;

  /// URL of the user's profile picture.
  final String? picture;

  /// When the profile was last updated.
  final String? updatedAt;

  factory TwitchProfile.fromJson(Map<String, dynamic> json) {
    return TwitchProfile(
      sub: json['sub']?.toString() ?? '',
      email: json['email']?.toString(),
      emailVerified: json['email_verified'] == true,
      preferredUsername: json['preferred_username']?.toString(),
      picture: json['picture']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'sub': sub,
        'email': email,
        'email_verified': emailVerified,
        'preferred_username': preferredUsername,
        'picture': picture,
        'updated_at': updatedAt,
      };
}

/// Configuration for the Twitch OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/twitch
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
///       twitchProvider(
///         TwitchProviderOptions(
///           clientId: env('TWITCH_CLIENT_ID'),
///           clientSecret: env('TWITCH_CLIENT_SECRET'),
///           redirectUri: 'https://example.com/auth/callback/twitch',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// ### Notes
///
/// - Uses OpenID Connect (OIDC).
/// - Requires `openid` and `user:read:email` scopes for email.
class TwitchProviderOptions {
  const TwitchProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['openid', 'user:read:email'],
  });

  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final List<String> scopes;
}

/// Twitch OAuth provider (OIDC).
///
/// ### Resources
/// - https://dev.twitch.tv/docs/authentication/getting-tokens-oidc/
/// - https://dev.twitch.tv/console/apps
OAuthProvider<TwitchProfile> twitchProvider(TwitchProviderOptions options) {
  return OAuthProvider<TwitchProfile>(
    id: 'twitch',
    name: 'Twitch',
    type: AuthProviderType.oidc,
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse('https://id.twitch.tv/oauth2/authorize'),
    tokenEndpoint: Uri.parse('https://id.twitch.tv/oauth2/token'),
    userInfoEndpoint: Uri.parse('https://id.twitch.tv/oauth2/userinfo'),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    useBasicAuth: false, // Twitch uses client_secret_post
    profileParser: TwitchProfile.fromJson,
    profileSerializer: (profile) => profile.toJson(),
    profile: (profile) {
      return AuthUser(
        id: profile.sub,
        name: profile.preferredUsername,
        email: profile.email,
        image: profile.picture,
        attributes: profile.toJson(),
      );
    },
  );
}

const List<String> _defaultTwitchScopes = ['openid', 'user:read:email'];

AuthProviderRegistration _twitchRegistration() {
  return AuthProviderRegistration(
    id: 'twitch',
    schema: ConfigSchema.object(
      description: 'Twitch OAuth provider settings (OIDC).',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the Twitch provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'Twitch OAuth client ID.',
          defaultValue: "{{ env.TWITCH_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'Twitch OAuth client secret.',
          defaultValue: "{{ env.TWITCH_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for Twitch callbacks.',
          defaultValue: "{{ env.TWITCH_REDIRECT_URI | default: '' }}",
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from Twitch.',
          items: ConfigSchema.string(),
          defaultValue: _defaultTwitchScopes,
        ),
      },
    ),
    builder: _buildTwitchProvider,
  );
}

AuthProvider? _buildTwitchProvider(Map<String, dynamic> config) {
  final enabled = parseBoolLike(
        config['enabled'],
        context: 'auth.providers.twitch.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.twitch.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.twitch.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.twitch.redirect_uri',
  );
  final scopes = parseStringList(
        config['scopes'],
        context: 'auth.providers.twitch.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultTwitchScopes;

  return twitchProvider(
    TwitchProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes.isEmpty ? _defaultTwitchScopes : scopes,
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

/// Register the Twitch OAuth provider with the registry.
void registerTwitchAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(_twitchRegistration(), overrideExisting: overrideExisting);
}
