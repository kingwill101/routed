import 'package:server_auth/src/core/core.dart';

/// Facebook user profile returned by the Graph API.
///
/// See [Facebook Graph API User](https://developers.facebook.com/docs/graph-api/reference/user/).
class FacebookProfile {
  /// Creates a new [FacebookProfile] with the given fields.
  const FacebookProfile({
    required this.id,
    this.email,
    this.name,
    this.firstName,
    this.lastName,
    this.picture,
  });

  /// Creates a [FacebookProfile] from a JSON map returned by the Facebook Graph API.
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

  /// Converts this profile to a JSON-serializable map.
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
  /// Creates a new [FacebookPicture].
  const FacebookPicture({this.url, this.width, this.height, this.isSilhouette});

  /// Creates a [FacebookPicture] from a JSON map.
  factory FacebookPicture.fromJson(Map<String, dynamic> json) {
    return FacebookPicture(
      url: json['url']?.toString(),
      width: json['width'] as int?,
      height: json['height'] as int?,
      isSilhouette: json['is_silhouette'] as bool?,
    );
  }

  /// URL of the profile picture.
  final String? url;

  /// Width of the picture in pixels.
  final int? width;

  /// Height of the picture in pixels.
  final int? height;

  /// Whether this is a default silhouette image.
  final bool? isSilhouette;

  /// Converts this picture data to a JSON-serializable map.
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
/// import 'package:server_auth/server_auth.dart';
/// import 'package:server_auth/server_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
///     store: InMemoryAuthStore(),
///     storeMode: AuthStoreMode.ephemeral,
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
  /// Creates a new [FacebookProviderOptions] configuration.
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

  /// The URI to redirect to after authentication.
  final String redirectUri;

  /// OAuth scopes to request. Defaults to `['email', 'public_profile']`.
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
