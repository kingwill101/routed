import 'package:routed/routed.dart';

/// Google user profile returned by the userinfo endpoint.
///
/// See [Get the authenticated user](https://developers.google.com/identity/openid-connect/openid-connect#an-id-tokens-payload).
class GoogleProfile {
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
/// import 'package:routed/auth.dart';
/// import 'package:routed_auth/routed_auth.dart';
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
  const GoogleProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['openid', 'profile', 'email'],
    this.accessType,
    this.prompt,
    this.hostedDomain,
  });

  final String clientId;
  final String clientSecret;
  final String redirectUri;
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

const List<String> _defaultGoogleScopes = ['openid', 'profile', 'email'];

AuthProviderRegistration _googleRegistration() {
  return AuthProviderRegistration(
    id: 'google',
    schema: ConfigSchema.object(
      description: 'Google OAuth provider settings.',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the Google provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'Google OAuth client ID.',
          defaultValue: "{{ env.GOOGLE_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'Google OAuth client secret.',
          defaultValue: "{{ env.GOOGLE_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for Google callbacks.',
          defaultValue: "{{ env.GOOGLE_REDIRECT_URI | default: '' }}",
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from Google.',
          items: ConfigSchema.string(),
          defaultValue: _defaultGoogleScopes,
        ),
        'access_type': ConfigSchema.string(
          description:
              'Access type (online/offline). Set offline for refresh tokens.',
          defaultValue: '',
        ),
        'prompt': ConfigSchema.string(
          description: 'Prompt behavior (none/consent/select_account).',
          defaultValue: '',
        ),
        'hosted_domain': ConfigSchema.string(
          description: 'Restrict to specific Google Workspace domain.',
          defaultValue: '',
        ),
      },
    ),
    builder: _buildGoogleProvider,
  );
}

AuthProvider? _buildGoogleProvider(Map<String, dynamic> config) {
  final enabled =
      parseBoolLike(
        config['enabled'],
        context: 'auth.providers.google.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.google.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.google.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.google.redirect_uri',
  );
  final scopes =
      parseStringList(
        config['scopes'],
        context: 'auth.providers.google.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultGoogleScopes;
  final accessType = _nullIfEmpty(
    parseStringLike(
      config['access_type'],
      context: 'auth.providers.google.access_type',
      allowEmpty: true,
      throwOnInvalid: true,
    ),
  );
  final prompt = _nullIfEmpty(
    parseStringLike(
      config['prompt'],
      context: 'auth.providers.google.prompt',
      allowEmpty: true,
      throwOnInvalid: true,
    ),
  );
  final hostedDomain = _nullIfEmpty(
    parseStringLike(
      config['hosted_domain'],
      context: 'auth.providers.google.hosted_domain',
      allowEmpty: true,
      throwOnInvalid: true,
    ),
  );

  return googleProvider(
    GoogleProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes.isEmpty ? _defaultGoogleScopes : scopes,
      accessType: accessType,
      prompt: prompt,
      hostedDomain: hostedDomain,
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

/// Register the Google OAuth provider with the registry.
void registerGoogleAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(_googleRegistration(), overrideExisting: overrideExisting);
}
