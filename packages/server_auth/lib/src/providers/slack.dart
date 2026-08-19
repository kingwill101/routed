import '../core/core.dart';

/// Slack user profile (OIDC).
///
/// See [Slack OpenID Connect](https://api.slack.com/authentication/sign-in-with-slack).
class SlackProfile {
  /// Creates a new [SlackProfile] with the given fields.
  const SlackProfile({
    required this.sub,
    this.email,
    this.emailVerified,
    this.name,
    this.picture,
    this.givenName,
    this.familyName,
    this.locale,
    this.slackTeamId,
    this.slackTeamName,
    this.slackTeamDomain,
    this.slackTeamImage,
  });

  /// Subject identifier (user ID).
  final String sub;

  /// User's email address.
  final String? email;

  /// Whether the email has been verified.
  final bool? emailVerified;

  /// User's full name.
  final String? name;

  /// URL of the user's profile picture.
  final String? picture;

  /// User's given name.
  final String? givenName;

  /// User's family name.
  final String? familyName;

  /// User's locale.
  final String? locale;

  /// Slack team/workspace ID.
  final String? slackTeamId;

  /// Slack team/workspace name.
  final String? slackTeamName;

  /// Slack team/workspace domain.
  final String? slackTeamDomain;

  /// Slack team/workspace image.
  final String? slackTeamImage;

  /// Creates a [SlackProfile] from a JSON map returned by the Slack OIDC userinfo endpoint.
  factory SlackProfile.fromJson(Map<String, dynamic> json) {
    return SlackProfile(
      sub: json['sub']?.toString() ?? '',
      email: json['email']?.toString(),
      emailVerified: json['email_verified'] == true,
      name: json['name']?.toString(),
      picture: json['picture']?.toString(),
      givenName: json['given_name']?.toString(),
      familyName: json['family_name']?.toString(),
      locale: json['locale']?.toString(),
      slackTeamId: json['https://slack.com/team_id']?.toString(),
      slackTeamName: json['https://slack.com/team_name']?.toString(),
      slackTeamDomain: json['https://slack.com/team_domain']?.toString(),
      slackTeamImage: json['https://slack.com/team_image_230']?.toString(),
    );
  }

  /// Converts this profile to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'sub': sub,
    'email': email,
    'email_verified': emailVerified,
    'name': name,
    'picture': picture,
    'given_name': givenName,
    'family_name': familyName,
    'locale': locale,
    'https://slack.com/team_id': slackTeamId,
    'https://slack.com/team_name': slackTeamName,
    'https://slack.com/team_domain': slackTeamDomain,
    'https://slack.com/team_image_230': slackTeamImage,
  };
}

/// Configuration for the Slack OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/slack
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
///       slackProvider(
///         SlackProviderOptions(
///           clientId: env('SLACK_CLIENT_ID'),
///           clientSecret: env('SLACK_CLIENT_SECRET'),
///           redirectUri: 'https://example.com/auth/callback/slack',
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
/// - Team information is included in the profile claims.
class SlackProviderOptions {
  /// Creates a new [SlackProviderOptions] configuration.
  const SlackProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['openid', 'profile', 'email'],
  });

  /// OAuth 2.0 client ID from the Slack API dashboard.
  final String clientId;

  /// OAuth 2.0 client secret from the Slack API dashboard.
  final String clientSecret;

  /// The URI to redirect to after authentication.
  final String redirectUri;

  /// OAuth scopes to request. Defaults to `['openid', 'profile', 'email']`.
  final List<String> scopes;
}

/// Slack OAuth provider (OIDC).
///
/// ### Resources
/// - https://api.slack.com/authentication/sign-in-with-slack
/// - https://api.slack.com/methods/openid.connect.userInfo
OAuthProvider<SlackProfile> slackProvider(SlackProviderOptions options) {
  return OAuthProvider<SlackProfile>(
    id: 'slack',
    name: 'Slack',
    type: AuthProviderType.oidc,
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse(
      'https://slack.com/openid/connect/authorize',
    ),
    tokenEndpoint: Uri.parse('https://slack.com/api/openid.connect.token'),
    userInfoEndpoint: Uri.parse(
      'https://slack.com/api/openid.connect.userInfo',
    ),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    profileParser: SlackProfile.fromJson,
    profileSerializer: (profile) => profile.toJson(),
    profile: (profile) {
      return AuthUser(
        id: profile.sub,
        name: profile.name,
        email: profile.email,
        image: profile.picture,
        attributes: profile.toJson(),
      );
    },
  );
}
