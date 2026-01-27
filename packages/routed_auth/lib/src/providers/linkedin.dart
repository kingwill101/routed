import 'package:routed/routed.dart';

/// LinkedIn user profile (OIDC).
///
/// See [LinkedIn Sign In with OpenID Connect](https://learn.microsoft.com/en-us/linkedin/consumer/integrations/self-serve/sign-in-with-linkedin-v2).
class LinkedInProfile {
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
/// import 'package:routed/auth.dart';
/// import 'package:routed_auth/routed_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
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
  const LinkedInProviderOptions({
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

const List<String> _defaultLinkedInScopes = ['openid', 'profile', 'email'];

AuthProviderRegistration _linkedInRegistration() {
  return AuthProviderRegistration(
    id: 'linkedin',
    schema: ConfigSchema.object(
      description: 'LinkedIn OAuth provider settings (OIDC).',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the LinkedIn provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'LinkedIn OAuth client ID.',
          defaultValue: "{{ env.LINKEDIN_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'LinkedIn OAuth client secret.',
          defaultValue: "{{ env.LINKEDIN_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for LinkedIn callbacks.',
          defaultValue: "{{ env.LINKEDIN_REDIRECT_URI | default: '' }}",
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from LinkedIn.',
          items: ConfigSchema.string(),
          defaultValue: _defaultLinkedInScopes,
        ),
      },
    ),
    builder: _buildLinkedInProvider,
  );
}

AuthProvider? _buildLinkedInProvider(Map<String, dynamic> config) {
  final enabled =
      parseBoolLike(
        config['enabled'],
        context: 'auth.providers.linkedin.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.linkedin.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.linkedin.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.linkedin.redirect_uri',
  );
  final scopes =
      parseStringList(
        config['scopes'],
        context: 'auth.providers.linkedin.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultLinkedInScopes;

  return linkedInProvider(
    LinkedInProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes.isEmpty ? _defaultLinkedInScopes : scopes,
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

/// Register the LinkedIn OAuth provider with the registry.
void registerLinkedInAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(
    _linkedInRegistration(),
    overrideExisting: overrideExisting,
  );
}
