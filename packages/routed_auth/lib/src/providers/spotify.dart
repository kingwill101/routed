import 'package:routed/routed.dart';

/// Spotify user profile.
///
/// See [Spotify Web API User Object](https://developer.spotify.com/documentation/web-api/reference/get-current-users-profile).
class SpotifyProfile {
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
  const SpotifyImage({this.url, this.width, this.height});

  final String? url;
  final int? width;
  final int? height;

  factory SpotifyImage.fromJson(Map<String, dynamic> json) {
    return SpotifyImage(
      url: json['url']?.toString(),
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'width': width,
        'height': height,
      };
}

/// Spotify followers object.
class SpotifyFollowers {
  const SpotifyFollowers({this.href, this.total});

  final String? href;
  final int? total;

  factory SpotifyFollowers.fromJson(Map<String, dynamic> json) {
    return SpotifyFollowers(
      href: json['href']?.toString(),
      total: json['total'] as int?,
    );
  }

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
/// import 'package:routed/auth.dart';
/// import 'package:routed_auth/routed_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
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
  const SpotifyProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['user-read-email'],
  });

  final String clientId;
  final String clientSecret;
  final String redirectUri;
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

const List<String> _defaultSpotifyScopes = ['user-read-email'];

AuthProviderRegistration _spotifyRegistration() {
  return AuthProviderRegistration(
    id: 'spotify',
    schema: ConfigSchema.object(
      description: 'Spotify OAuth provider settings.',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the Spotify provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'Spotify OAuth client ID.',
          defaultValue: "{{ env.SPOTIFY_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'Spotify OAuth client secret.',
          defaultValue: "{{ env.SPOTIFY_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for Spotify callbacks.',
          defaultValue: "{{ env.SPOTIFY_REDIRECT_URI | default: '' }}",
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from Spotify.',
          items: ConfigSchema.string(),
          defaultValue: _defaultSpotifyScopes,
        ),
      },
    ),
    builder: _buildSpotifyProvider,
  );
}

AuthProvider? _buildSpotifyProvider(Map<String, dynamic> config) {
  final enabled = parseBoolLike(
        config['enabled'],
        context: 'auth.providers.spotify.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.spotify.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.spotify.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.spotify.redirect_uri',
  );
  final scopes = parseStringList(
        config['scopes'],
        context: 'auth.providers.spotify.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultSpotifyScopes;

  return spotifyProvider(
    SpotifyProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes.isEmpty ? _defaultSpotifyScopes : scopes,
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

/// Register the Spotify OAuth provider with the registry.
void registerSpotifyAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(_spotifyRegistration(), overrideExisting: overrideExisting);
}
