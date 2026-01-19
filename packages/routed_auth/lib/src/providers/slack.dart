import 'package:routed/routed.dart';

/// Slack user profile (OIDC).
///
/// See [Slack OpenID Connect](https://api.slack.com/authentication/sign-in-with-slack).
class SlackProfile {
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
/// import 'package:routed/auth.dart';
/// import 'package:routed_auth/routed_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
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
  const SlackProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['openid', 'profile', 'email'],
  });

  final String clientId;
  final String clientSecret;
  final String redirectUri;
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
    authorizationEndpoint: Uri.parse('https://slack.com/openid/connect/authorize'),
    tokenEndpoint: Uri.parse('https://slack.com/api/openid.connect.token'),
    userInfoEndpoint: Uri.parse('https://slack.com/api/openid.connect.userInfo'),
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

const List<String> _defaultSlackScopes = ['openid', 'profile', 'email'];

AuthProviderRegistration _slackRegistration() {
  return AuthProviderRegistration(
    id: 'slack',
    schema: ConfigSchema.object(
      description: 'Slack OAuth provider settings (OIDC).',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the Slack provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'Slack OAuth client ID.',
          defaultValue: "{{ env.SLACK_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'Slack OAuth client secret.',
          defaultValue: "{{ env.SLACK_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for Slack callbacks.',
          defaultValue: "{{ env.SLACK_REDIRECT_URI | default: '' }}",
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from Slack.',
          items: ConfigSchema.string(),
          defaultValue: _defaultSlackScopes,
        ),
      },
    ),
    builder: _buildSlackProvider,
  );
}

AuthProvider? _buildSlackProvider(Map<String, dynamic> config) {
  final enabled = parseBoolLike(
        config['enabled'],
        context: 'auth.providers.slack.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.slack.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.slack.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.slack.redirect_uri',
  );
  final scopes = parseStringList(
        config['scopes'],
        context: 'auth.providers.slack.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultSlackScopes;

  return slackProvider(
    SlackProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes.isEmpty ? _defaultSlackScopes : scopes,
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

/// Register the Slack OAuth provider with the registry.
void registerSlackAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(_slackRegistration(), overrideExisting: overrideExisting);
}
