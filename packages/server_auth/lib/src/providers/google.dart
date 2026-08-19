import '../core/core.dart';

/// Google user profile returned by the userinfo endpoint.
///
/// See [Get the authenticated user](https://developers.google.com/identity/openid-connect/openid-connect#an-id-tokens-payload).
class GoogleProfile {
  /// Creates a new [GoogleProfile] with the given fields.
  const GoogleProfile({
    required this.sub,
    this.email,
    this.emailVerified,
    this.name,
    this.picture,
    this.givenName,
    this.familyName,
    this.locale,
    this.hd,
  });

  /// Unique identifier for the user (subject).
  final String sub;

  /// User's email address.
  final String? email;

  /// Whether the email has been verified.
  final bool? emailVerified;

  /// User's full name.
  final String? name;

  /// URL of the user's profile picture.
  final String? picture;

  /// User's given/first name.
  final String? givenName;

  /// User's family/last name.
  final String? familyName;

  /// User's locale.
  final String? locale;

  /// Hosted domain (for Google Workspace accounts).
  final String? hd;

  /// Creates a [GoogleProfile] from a JSON map returned by the Google userinfo endpoint.
  factory GoogleProfile.fromJson(Map<String, dynamic> json) {
    return GoogleProfile(
      sub: json['sub']?.toString() ?? '',
      email: json['email']?.toString(),
      emailVerified: json['email_verified'] == true,
      name: json['name']?.toString(),
      picture: json['picture']?.toString(),
      givenName: json['given_name']?.toString(),
      familyName: json['family_name']?.toString(),
      locale: json['locale']?.toString(),
      hd: json['hd']?.toString(),
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
    'hd': hd,
  };
}

/// Configuration for the Google OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/google
/// ```
///
/// ### Usage
/// ```dart
/// import 'package:server_auth/server_auth.dart';
/// import 'package:server_auth/server_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
///     providers: [
///       googleProvider(
///         GoogleProviderOptions(
///           clientId: env('GOOGLE_CLIENT_ID'),
///           clientSecret: env('GOOGLE_CLIENT_SECRET'),
///           redirectUri: 'https://example.com/auth/callback/google',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// ### Notes
///
/// - Uses OpenID Connect (OIDC) with OAuth 2.0.
/// - Set `accessType: 'offline'` and `prompt: 'consent'` to receive refresh tokens.
/// - Use `hd` parameter to restrict to specific Google Workspace domains.
class GoogleProviderOptions {
  /// Creates a new [GoogleProviderOptions] configuration.
  const GoogleProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['openid', 'profile', 'email'],
    this.accessType,
    this.prompt,
    this.hostedDomain,
  });

  /// OAuth 2.0 client ID from the Google Cloud Console.
  final String clientId;

  /// OAuth 2.0 client secret from the Google Cloud Console.
  final String clientSecret;

  /// The URI to redirect to after authentication.
  final String redirectUri;

  /// OAuth scopes to request. Defaults to `['openid', 'profile', 'email']`.
  final List<String> scopes;

  /// Access type for token requests. Set to 'offline' for refresh tokens.
  final String? accessType;

  /// Prompt behavior. Set to 'consent' to force consent screen.
  final String? prompt;

  /// Restrict login to specific Google Workspace domain.
  final String? hostedDomain;
}

/// Google OAuth provider.
///
/// Based on Google's OAuth 2.0 and OpenID Connect documentation.
///
/// ### Resources
/// - https://developers.google.com/identity/protocols/oauth2
/// - https://console.developers.google.com/apis/credentials
/// - https://developers.google.com/identity/openid-connect/openid-connect
///
/// ### Example
/// ```dart
/// final provider = googleProvider(
///   GoogleProviderOptions(
///     clientId: 'client-id',
///     clientSecret: 'client-secret',
///     redirectUri: 'https://example.com/auth/callback/google',
///   ),
/// );
/// ```
OAuthProvider<GoogleProfile> googleProvider(GoogleProviderOptions options) {
  final authorizationParams = <String, String>{};
  if (options.accessType != null) {
    authorizationParams['access_type'] = options.accessType!;
  }
  if (options.prompt != null) {
    authorizationParams['prompt'] = options.prompt!;
  }
  if (options.hostedDomain != null) {
    authorizationParams['hd'] = options.hostedDomain!;
  }

  return OAuthProvider<GoogleProfile>(
    id: 'google',
    name: 'Google',
    type: AuthProviderType.oidc,
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse(
      'https://accounts.google.com/o/oauth2/v2/auth',
    ),
    tokenEndpoint: Uri.parse('https://oauth2.googleapis.com/token'),
    userInfoEndpoint: Uri.parse(
      'https://openidconnect.googleapis.com/v1/userinfo',
    ),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    authorizationParams: authorizationParams,
    profileParser: GoogleProfile.fromJson,
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
