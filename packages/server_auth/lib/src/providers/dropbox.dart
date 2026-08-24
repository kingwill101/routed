import 'dart:convert';

import 'package:server_auth/src/core/core.dart';

/// Dropbox user profile returned by the `/2/users/get_current_account` endpoint.
///
/// See [Dropbox API documentation](https://www.dropbox.com/developers/documentation/http/documentation#users-get_current_account).
class DropboxProfile {
  /// Creates a new [DropboxProfile] with the given fields.
  const DropboxProfile({
    required this.accountId,
    this.email,
    this.emailVerified,
    this.name,
    this.profilePhotoUrl,
    this.disabled,
    this.country,
    this.locale,
    this.isPaired,
    this.accountType,
  });

  /// Creates a [DropboxProfile] from a JSON map returned by the Dropbox API.
  factory DropboxProfile.fromJson(Map<String, dynamic> json) {
    // Extract nested name object
    final nameObj = json['name'] as Map<String, dynamic>?;
    final displayName = nameObj?['display_name']?.toString();

    return DropboxProfile(
      accountId: json['account_id']?.toString() ?? '',
      email: json['email']?.toString(),
      emailVerified: json['email_verified'] == true,
      name: displayName,
      profilePhotoUrl: json['profile_photo_url']?.toString(),
      disabled: json['disabled'] == true,
      country: json['country']?.toString(),
      locale: json['locale']?.toString(),
      isPaired: json['is_paired'] == true,
      accountType: (json['account_type'] as Map<String, dynamic>?)?['.tag']
          ?.toString(),
    );
  }

  /// Unique identifier for the Dropbox account.
  final String accountId;

  /// User's email address.
  final String? email;

  /// Whether the email has been verified.
  final bool? emailVerified;

  /// User's display name.
  final String? name;

  /// URL of the user's profile photo.
  final String? profilePhotoUrl;

  /// Whether the account is disabled.
  final bool? disabled;

  /// User's two-letter country code.
  final String? country;

  /// User's locale.
  final String? locale;

  /// Whether the account is paired.
  final bool? isPaired;

  /// Account type (basic, pro, business).
  final String? accountType;

  /// Converts this profile to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'account_id': accountId,
    'email': email,
    'email_verified': emailVerified,
    'name': {'display_name': name},
    'profile_photo_url': profilePhotoUrl,
    'disabled': disabled,
    'country': country,
    'locale': locale,
    'is_paired': isPaired,
    'account_type': accountType != null ? {'.tag': accountType} : null,
  };
}

/// Configuration for the Dropbox OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/dropbox
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
///       dropboxProvider(
///         DropboxProviderOptions(
///           clientId: env('DROPBOX_CLIENT_ID'),
///           clientSecret: env('DROPBOX_CLIENT_SECRET'),
///           redirectUri: 'https://example.com/auth/callback/dropbox',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// ### Notes
///
/// - Uses OAuth 2.0.
/// - Set `tokenAccessType: 'offline'` to receive refresh tokens.
/// - The userinfo endpoint requires a POST request with no body.
class DropboxProviderOptions {
  /// Creates a new [DropboxProviderOptions] configuration.
  const DropboxProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['account_info.read'],
    this.tokenAccessType = 'offline',
  });

  /// OAuth 2.0 app key from the Dropbox App Console.
  final String clientId;

  /// OAuth 2.0 app secret from the Dropbox App Console.
  final String clientSecret;

  /// The URI to redirect to after authentication.
  final String redirectUri;

  /// OAuth scopes to request. Defaults to `['account_info.read']`.
  final List<String> scopes;

  /// Token access type. Set to 'offline' for refresh tokens.
  final String? tokenAccessType;
}

/// Dropbox OAuth provider.
///
/// Based on Dropbox's OAuth 2.0 documentation.
///
/// ### Resources
/// - https://developers.dropbox.com/oauth-guide
/// - https://www.dropbox.com/developers/apps
/// - https://www.dropbox.com/developers/documentation/http/documentation
///
/// ### Example
/// ```dart
/// final provider = dropboxProvider(
///   DropboxProviderOptions(
///     clientId: 'client-id',
///     clientSecret: 'client-secret',
///     redirectUri: 'https://example.com/auth/callback/dropbox',
///   ),
/// );
/// ```
OAuthProvider<DropboxProfile> dropboxProvider(DropboxProviderOptions options) {
  final authorizationParams = <String, String>{
    'scope': options.scopes.join(' '),
  };
  if (options.tokenAccessType != null) {
    authorizationParams['token_access_type'] = options.tokenAccessType!;
  }

  return OAuthProvider<DropboxProfile>(
    id: 'dropbox',
    name: 'Dropbox',
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse(
      'https://www.dropbox.com/oauth2/authorize',
    ),
    tokenEndpoint: Uri.parse('https://api.dropboxapi.com/oauth2/token'),
    userInfoEndpoint: Uri.parse(
      'https://api.dropboxapi.com/2/users/get_current_account',
    ),
    // Dropbox requires POST for userinfo, not GET
    userInfoRequest: (token, httpClient, endpoint) async {
      final response = await httpClient.post(
        endpoint,
        headers: {
          'Authorization': 'Bearer ${token.accessToken}',
          'Content-Type': 'application/json',
        },
        body: 'null', // Dropbox requires a body, even if null
      );
      if (response.statusCode != 200) {
        throw AuthFlowException('dropbox_userinfo_failed');
      }
      if (response.body.length > maxOAuthResponseCharacters) {
        throw AuthFlowException('dropbox_userinfo_failed');
      }
      return json.decode(response.body) as Map<String, dynamic>;
    },
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    authorizationParams: authorizationParams,
    profileParser: DropboxProfile.fromJson,
    profileSerializer: (profile) => profile.toJson(),
    profile: (profile) {
      return AuthUser(
        id: profile.accountId,
        name: profile.name,
        email: profile.email,
        image: profile.profilePhotoUrl,
        attributes: profile.toJson(),
      );
    },
  );
}
