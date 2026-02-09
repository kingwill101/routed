import 'dart:convert';

import 'package:routed/routed.dart';

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
/// import 'package:routed/auth.dart';
/// import 'package:routed_auth/routed_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
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
    type: AuthProviderType.oauth,
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
        throw Exception('Failed to fetch Dropbox user info: ${response.body}');
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

const List<String> _defaultDropboxScopes = ['account_info.read'];

AuthProviderRegistration _dropboxRegistration() {
  return AuthProviderRegistration(
    id: 'dropbox',
    schema: ConfigSchema.object(
      description: 'Dropbox OAuth provider settings.',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the Dropbox provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'Dropbox OAuth client ID (App key).',
          defaultValue: "{{ env.DROPBOX_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'Dropbox OAuth client secret (App secret).',
          defaultValue: "{{ env.DROPBOX_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for Dropbox callbacks.',
          defaultValue: "{{ env.DROPBOX_REDIRECT_URI | default: '' }}",
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from Dropbox.',
          items: ConfigSchema.string(),
          defaultValue: _defaultDropboxScopes,
        ),
        'token_access_type': ConfigSchema.string(
          description:
              'Token access type (online/offline). Set offline for refresh tokens.',
          defaultValue: 'offline',
        ),
      },
    ),
    builder: _buildDropboxProvider,
  );
}

AuthProvider? _buildDropboxProvider(Map<String, dynamic> config) {
  final enabled =
      parseBoolLike(
        config['enabled'],
        context: 'auth.providers.dropbox.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.dropbox.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.dropbox.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.dropbox.redirect_uri',
  );
  final scopes =
      parseStringList(
        config['scopes'],
        context: 'auth.providers.dropbox.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultDropboxScopes;
  final tokenAccessType = _nullIfEmpty(
    parseStringLike(
      config['token_access_type'],
      context: 'auth.providers.dropbox.token_access_type',
      allowEmpty: true,
      throwOnInvalid: true,
    ),
  );

  return dropboxProvider(
    DropboxProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes.isEmpty ? _defaultDropboxScopes : scopes,
      tokenAccessType: tokenAccessType ?? 'offline',
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

String? _nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Register the Dropbox OAuth provider with the registry.
void registerDropboxAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(_dropboxRegistration(), overrideExisting: overrideExisting);
}
