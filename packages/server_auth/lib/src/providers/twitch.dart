import 'package:server_auth/src/core/core.dart';

/// Twitch user profile (OIDC).
///
/// See [Twitch OIDC](https://dev.twitch.tv/docs/authentication/getting-tokens-oidc/).
class TwitchProfile {
  /// Creates a new [TwitchProfile] with the given fields.
  const TwitchProfile({
    required this.sub,
    this.email,
    this.emailVerified,
    this.preferredUsername,
    this.picture,
    this.updatedAt,
  });

  /// Creates a [TwitchProfile] from a JSON map returned by the Twitch OIDC userinfo endpoint.
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

  /// Converts this profile to a JSON-serializable map.
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
/// import 'package:server_auth/server_auth.dart';
/// import 'package:server_auth/server_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
///     store: InMemoryAuthStore(),
///     storeMode: AuthStoreMode.ephemeral,
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
  /// Creates a new [TwitchProviderOptions] configuration.
  const TwitchProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['openid', 'user:read:email'],
  });

  /// OAuth 2.0 client ID from the Twitch Developer Console.
  final String clientId;

  /// OAuth 2.0 client secret from the Twitch Developer Console.
  final String clientSecret;

  /// The URI to redirect to after authentication.
  final String redirectUri;

  /// OAuth scopes to request. Defaults to `['openid', 'user:read:email']`.
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
