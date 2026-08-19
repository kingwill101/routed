import '../core/core.dart';

/// Spotify user profile.
///
/// See [Spotify Web API User Object](https://developer.spotify.com/documentation/web-api/reference/get-current-users-profile).
class SpotifyProfile {
  /// Creates a new [SpotifyProfile] with the given fields.
  const SpotifyProfile({
    required this.id,
    this.displayName,
    this.email,
    this.images,
    this.country,
    this.href,
    this.uri,
    this.product,
    this.explicitContent,
    this.followers,
  });

  /// User's Spotify user ID.
  final String id;

  /// User's display name.
  final String? displayName;

  /// User's email address.
  final String? email;

  /// User's profile images.
  final List<SpotifyImage>? images;

  /// User's country code.
  final String? country;

  /// Link to the user's profile.
  final String? href;

  /// Spotify URI for the user.
  final String? uri;

  /// User's subscription level (premium, free, etc.).
  final String? product;

  /// Explicit content settings.
  final Map<String, dynamic>? explicitContent;

  /// Follower information.
  final SpotifyFollowers? followers;

  /// Creates a [SpotifyProfile] from a JSON map returned by the Spotify Web API.
  factory SpotifyProfile.fromJson(Map<String, dynamic> json) {
    List<SpotifyImage>? images;
    if (json['images'] is List) {
      images = (json['images'] as List)
          .whereType<Map<String, dynamic>>()
          .map(SpotifyImage.fromJson)
          .toList();
    }
    SpotifyFollowers? followers;
    if (json['followers'] is Map<String, dynamic>) {
      followers = SpotifyFollowers.fromJson(
        json['followers'] as Map<String, dynamic>,
      );
    }
    return SpotifyProfile(
      id: json['id']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      email: json['email']?.toString(),
      images: images,
      country: json['country']?.toString(),
      href: json['href']?.toString(),
      uri: json['uri']?.toString(),
      product: json['product']?.toString(),
      explicitContent: json['explicit_content'] as Map<String, dynamic>?,
      followers: followers,
    );
  }

  /// Converts this profile to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'display_name': displayName,
    'email': email,
    'images': images?.map((i) => i.toJson()).toList(),
    'country': country,
    'href': href,
    'uri': uri,
    'product': product,
    'explicit_content': explicitContent,
    'followers': followers?.toJson(),
  };

  /// Returns the URL of the first profile image.
  String? get imageUrl => images?.isNotEmpty == true ? images!.first.url : null;
}

/// Spotify image object.
class SpotifyImage {
  /// Creates a new [SpotifyImage].
  const SpotifyImage({this.url, this.width, this.height});

  /// URL of the image.
  final String? url;

  /// Width of the image in pixels.
  final int? width;

  /// Height of the image in pixels.
  final int? height;

  /// Creates a [SpotifyImage] from a JSON map.
  factory SpotifyImage.fromJson(Map<String, dynamic> json) {
    return SpotifyImage(
      url: json['url']?.toString(),
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }

  /// Converts this image to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'url': url,
    'width': width,
    'height': height,
  };
}

/// Spotify followers object.
class SpotifyFollowers {
  /// Creates a new [SpotifyFollowers].
  const SpotifyFollowers({this.href, this.total});

  /// Link to the followers endpoint (always `null` per Spotify docs).
  final String? href;

  /// Total number of followers.
  final int? total;

  /// Creates a [SpotifyFollowers] from a JSON map.
  factory SpotifyFollowers.fromJson(Map<String, dynamic> json) {
    return SpotifyFollowers(
      href: json['href']?.toString(),
      total: json['total'] as int?,
    );
  }

  /// Converts this follower data to a JSON-serializable map.
  Map<String, dynamic> toJson() => {'href': href, 'total': total};
}

/// Configuration for the Spotify OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/spotify
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
///       spotifyProvider(
///         SpotifyProviderOptions(
///           clientId: env('SPOTIFY_CLIENT_ID'),
///           clientSecret: env('SPOTIFY_CLIENT_SECRET'),
///           redirectUri: 'https://example.com/auth/callback/spotify',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
class SpotifyProviderOptions {
  /// Creates a new [SpotifyProviderOptions] configuration.
  const SpotifyProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['user-read-email'],
  });

  /// OAuth 2.0 client ID from the Spotify Developer Dashboard.
  final String clientId;

  /// OAuth 2.0 client secret from the Spotify Developer Dashboard.
  final String clientSecret;

  /// The URI to redirect to after authentication.
  final String redirectUri;

  /// OAuth scopes to request. Defaults to `['user-read-email', 'user-read-private']`.
  final List<String> scopes;
}

/// Spotify OAuth provider.
///
/// ### Resources
/// - https://developer.spotify.com/documentation/web-api/tutorials/code-flow
/// - https://developer.spotify.com/documentation/web-api/reference/get-current-users-profile
OAuthProvider<SpotifyProfile> spotifyProvider(SpotifyProviderOptions options) {
  return OAuthProvider<SpotifyProfile>(
    id: 'spotify',
    name: 'Spotify',
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse('https://accounts.spotify.com/authorize'),
    tokenEndpoint: Uri.parse('https://accounts.spotify.com/api/token'),
    userInfoEndpoint: Uri.parse('https://api.spotify.com/v1/me'),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    profileParser: SpotifyProfile.fromJson,
    profileSerializer: (profile) => profile.toJson(),
    profile: (profile) {
      return AuthUser(
        id: profile.id,
        name: profile.displayName,
        email: profile.email,
        image: profile.imageUrl,
        attributes: profile.toJson(),
      );
    },
  );
}
