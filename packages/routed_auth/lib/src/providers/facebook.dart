import 'package:routed/routed.dart';

/// Facebook user profile returned by the Graph API.
///
/// See [Facebook Graph API User](https://developers.facebook.com/docs/graph-api/reference/user/).
class FacebookProfile {
  const FacebookProfile({
    required this.id,
    this.email,
    this.name,
    this.firstName,
    this.lastName,
    this.picture,
  });

  /// Unique identifier for the user.
  final String id;

  /// User's email address.
  final String? email;

  /// User's full name.
  final String? name;

  /// User's first name.
  final String? firstName;

  /// User's last name.
  final String? lastName;

  /// User's profile picture data.
  final FacebookPicture? picture;

  factory FacebookProfile.fromJson(Map<String, dynamic> json) {
    FacebookPicture? picture;
    if (json['picture'] is Map<String, dynamic>) {
      final pictureData = json['picture']['data'] as Map<String, dynamic>?;
      if (pictureData != null) {
        picture = FacebookPicture.fromJson(pictureData);
      }
    }
    return FacebookProfile(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString(),
      name: json['name']?.toString(),
      firstName: json['first_name']?.toString(),
      lastName: json['last_name']?.toString(),
      picture: picture,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'first_name': firstName,
    'last_name': lastName,
    'picture': picture?.toJson(),
  };
}

/// Facebook profile picture data.
class FacebookPicture {
  const FacebookPicture({this.url, this.width, this.height, this.isSilhouette});

  final String? url;
  final int? width;
  final int? height;
  final bool? isSilhouette;

  factory FacebookPicture.fromJson(Map<String, dynamic> json) {
    return FacebookPicture(
      url: json['url']?.toString(),
      width: json['width'] as int?,
      height: json['height'] as int?,
      isSilhouette: json['is_silhouette'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'width': width,
    'height': height,
    'is_silhouette': isSilhouette,
  };
}

/// Configuration for the Facebook OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/facebook
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
///       facebookProvider(
///         FacebookProviderOptions(
///           clientId: env('FACEBOOK_APP_ID'),
///           clientSecret: env('FACEBOOK_APP_SECRET'),
///           redirectUri: 'https://example.com/auth/callback/facebook',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
class FacebookProviderOptions {
  const FacebookProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['email', 'public_profile'],
  });

  /// Facebook App ID.
  final String clientId;

  /// Facebook App Secret.
  final String clientSecret;

  final String redirectUri;
  final List<String> scopes;
}

/// Facebook OAuth provider.
///
/// ### Resources
/// - https://developers.facebook.com/docs/facebook-login/manually-build-a-login-flow
/// - https://developers.facebook.com/docs/graph-api/reference/user/
OAuthProvider<FacebookProfile> facebookProvider(
  FacebookProviderOptions options,
) {
  return OAuthProvider<FacebookProfile>(
    id: 'facebook',
    name: 'Facebook',
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse(
      'https://www.facebook.com/v18.0/dialog/oauth',
    ),
    tokenEndpoint: Uri.parse(
      'https://graph.facebook.com/v18.0/oauth/access_token',
    ),
    userInfoEndpoint: Uri.parse(
      'https://graph.facebook.com/me?fields=id,name,email,first_name,last_name,picture',
    ),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    profileParser: FacebookProfile.fromJson,
    profileSerializer: (profile) => profile.toJson(),
    profile: (profile) {
      return AuthUser(
        id: profile.id,
        name: profile.name,
        email: profile.email,
        image: profile.picture?.url,
        attributes: profile.toJson(),
      );
    },
  );
}

const List<String> _defaultFacebookScopes = ['email', 'public_profile'];

AuthProviderRegistration _facebookRegistration() {
  return AuthProviderRegistration(
    id: 'facebook',
    schema: ConfigSchema.object(
      description: 'Facebook OAuth provider settings.',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the Facebook provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'Facebook App ID.',
          defaultValue: "{{ env.FACEBOOK_APP_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'Facebook App Secret.',
          defaultValue: "{{ env.FACEBOOK_APP_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for Facebook callbacks.',
          defaultValue: "{{ env.FACEBOOK_REDIRECT_URI | default: '' }}",
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from Facebook.',
          items: ConfigSchema.string(),
          defaultValue: _defaultFacebookScopes,
        ),
      },
    ),
    builder: _buildFacebookProvider,
  );
}

AuthProvider? _buildFacebookProvider(Map<String, dynamic> config) {
  final enabled =
      parseBoolLike(
        config['enabled'],
        context: 'auth.providers.facebook.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.facebook.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.facebook.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.facebook.redirect_uri',
  );
  final scopes =
      parseStringList(
        config['scopes'],
        context: 'auth.providers.facebook.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultFacebookScopes;

  return facebookProvider(
    FacebookProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes.isEmpty ? _defaultFacebookScopes : scopes,
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

/// Register the Facebook OAuth provider with the registry.
void registerFacebookAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(
    _facebookRegistration(),
    overrideExisting: overrideExisting,
  );
}
