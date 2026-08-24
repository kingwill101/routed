import 'package:server_auth/src/core/core.dart';

/// LinkedIn user profile (OIDC).
///
/// See [LinkedIn Sign In with OpenID Connect](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2).
class LinkedInProfile {
  /// Creates a new [LinkedInProfile] with the given fields.
  const LinkedInProfile({
    required this.sub,
    this.email,
    this.emailVerified,
    this.name,
    this.picture,
    this.givenName,
    this.familyName,
    this.locale,
  });

  /// Creates a [LinkedInProfile] from a JSON map returned by the LinkedIn OIDC userinfo endpoint.
  factory LinkedInProfile.fromJson(Map<String, dynamic> json) {
    return LinkedInProfile(
      sub: json['sub']?.toString() ?? '',
      email: json['email']?.toString(),
      emailVerified: json['email_verified'] == true,
      name: json['name']?.toString(),
      picture: json['picture']?.toString(),
      givenName: json['given_name']?.toString(),
      familyName: json['family_name']?.toString(),
      locale: json['locale']?.toString(),
    );
  }

  /// Subject identifier (member ID).
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
  };
}

/// Configuration for the LinkedIn OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/linkedin
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
///       linkedInProvider(
///         LinkedInProviderOptions(
///           clientId: env('LINKEDIN_CLIENT_ID'),
///           clientSecret: env('LINKEDIN_CLIENT_SECRET'),
///           redirectUri: 'https://example.com/auth/callback/linkedin',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// ### Notes
///
/// - Uses OpenID Connect (Sign In with LinkedIn v2).
/// - Legacy v1 API is deprecated.
class LinkedInProviderOptions {
  /// Creates a new [LinkedInProviderOptions] configuration.
  const LinkedInProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['openid', 'profile', 'email'],
  });

  /// OAuth 2.0 client ID from the LinkedIn Developer Portal.
  final String clientId;

  /// OAuth 2.0 client secret from the LinkedIn Developer Portal.
  final String clientSecret;

  /// The URI to redirect to after authentication.
  final String redirectUri;

  /// OAuth scopes to request. Defaults to `['openid', 'profile', 'email']`.
  final List<String> scopes;
}

/// LinkedIn OAuth provider (OIDC).
///
/// ### Resources
/// - https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2
/// - https://www.linkedin.com/developers/apps
OAuthProvider<LinkedInProfile> linkedInProvider(
  LinkedInProviderOptions options,
) {
  return OAuthProvider<LinkedInProfile>(
    id: 'linkedin',
    name: 'LinkedIn',
    type: AuthProviderType.oidc,
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse(
      'https://www.linkedin.com/oauth/v2/authorization',
    ),
    tokenEndpoint: Uri.parse('https://www.linkedin.com/oauth/v2/accessToken'),
    userInfoEndpoint: Uri.parse('https://api.linkedin.com/v2/userinfo'),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    profileParser: LinkedInProfile.fromJson,
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
