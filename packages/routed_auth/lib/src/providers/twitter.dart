import 'package:routed/routed.dart';

/// Twitter/X user profile returned by the API.
///
/// See [Users lookup](https://developer.x.com/en/docs/twitter-api/users/lookup/api-reference/get-users-me).
class TwitterProfile {
  /// Creates a new [TwitterProfile] with the given fields.
  const TwitterProfile({
    required this.id,
    required this.name,
    required this.username,
    this.description,
    this.profileImageUrl,
    this.location,
    this.url,
    this.verified,
    this.protected,
    this.createdAt,
    this.pinnedTweetId,
  });

  /// Unique identifier of the user.
  final String id;

  /// Display name of the user.
  final String name;

  /// Username (handle) of the user.
  final String username;

  /// Bio/description of the user.
  final String? description;

  /// URL of the user's profile image.
  final String? profileImageUrl;

  /// User's location.
  final String? location;

  /// User's website URL.
  final String? url;

  /// Whether the user is verified.
  final bool? verified;

  /// Whether the user's tweets are protected.
  final bool? protected;

  /// When the user account was created.
  final String? createdAt;

  /// ID of the user's pinned tweet.
  final String? pinnedTweetId;

  /// Creates a [TwitterProfile] from a JSON map returned by the Twitter API v2.
  factory TwitterProfile.fromJson(Map<String, dynamic> json) {
    // Twitter API wraps user data in 'data' object
    final data = json['data'] as Map<String, dynamic>? ?? json;
    return TwitterProfile(
      id: data['id']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      username: data['username']?.toString() ?? '',
      description: data['description']?.toString(),
      profileImageUrl: data['profile_image_url']?.toString(),
      location: data['location']?.toString(),
      url: data['url']?.toString(),
      verified: data['verified'] as bool?,
      protected: data['protected'] as bool?,
      createdAt: data['created_at']?.toString(),
      pinnedTweetId: data['pinned_tweet_id']?.toString(),
    );
  }

  /// Converts this profile to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'username': username,
    'description': description,
    'profile_image_url': profileImageUrl,
    'location': location,
    'url': url,
    'verified': verified,
    'protected': protected,
    'created_at': createdAt,
    'pinned_tweet_id': pinnedTweetId,
  };
}

/// Configuration for the Twitter/X OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/twitter
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
///       twitterProvider(
///         TwitterProviderOptions(
///           clientId: env('TWITTER_CLIENT_ID'),
///           clientSecret: env('TWITTER_CLIENT_SECRET'),
///           redirectUri: 'https://example.com/auth/callback/twitter',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// ### Notes
///
/// - Uses OAuth 2.0 with PKCE.
/// - Twitter API v2 is used for user info.
/// - You must enable "Request email from users" in app permissions.
class TwitterProviderOptions {
  /// Creates a new [TwitterProviderOptions] configuration.
  const TwitterProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['users.read', 'tweet.read', 'offline.access'],
  });

  /// OAuth 2.0 client ID from the Twitter Developer Portal.
  final String clientId;

  /// OAuth 2.0 client secret from the Twitter Developer Portal.
  final String clientSecret;

  /// The URI to redirect to after authentication.
  final String redirectUri;

  /// OAuth scopes to request. Defaults to `['tweet.read', 'users.read']`.
  final List<String> scopes;
}

/// Twitter/X OAuth provider.
///
/// Based on Twitter's OAuth 2.0 documentation.
///
/// ### Resources
/// - https://developer.x.com/en/docs/authentication/oauth-2-0/authorization-code
/// - https://developer.x.com/en/docs/twitter-api/users/lookup/api-reference/get-users-me
///
/// ### Example
/// ```dart
/// final provider = twitterProvider(
///   TwitterProviderOptions(
///     clientId: 'client-id',
///     clientSecret: 'client-secret',
///     redirectUri: 'https://example.com/auth/callback/twitter',
///   ),
/// );
/// ```
OAuthProvider<TwitterProfile> twitterProvider(TwitterProviderOptions options) {
  return OAuthProvider<TwitterProfile>(
    id: 'twitter',
    name: 'Twitter',
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse('https://x.com/i/oauth2/authorize'),
    tokenEndpoint: Uri.parse('https://api.x.com/2/oauth2/token'),
    userInfoEndpoint: Uri.parse(
      'https://api.x.com/2/users/me?user.fields=profile_image_url',
    ),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    usePkce: true,
    profileParser: TwitterProfile.fromJson,
    profileSerializer: (profile) => profile.toJson(),
    profile: (profile) {
      return AuthUser(
        id: profile.id,
        name: profile.name,
        email: null, // Twitter doesn't return email by default
        image: profile.profileImageUrl,
        attributes: profile.toJson(),
      );
    },
  );
}

const List<String> _defaultTwitterScopes = [
  'users.read',
  'tweet.read',
  'offline.access',
];

AuthProviderRegistration _twitterRegistration() {
  return AuthProviderRegistration(
    id: 'twitter',
    schema: ConfigSchema.object(
      description: 'Twitter/X OAuth provider settings.',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the Twitter provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'Twitter OAuth client ID.',
          defaultValue: "{{ env.TWITTER_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'Twitter OAuth client secret.',
          defaultValue: "{{ env.TWITTER_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for Twitter callbacks.',
          defaultValue: "{{ env.TWITTER_REDIRECT_URI | default: '' }}",
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from Twitter.',
          items: ConfigSchema.string(),
          defaultValue: _defaultTwitterScopes,
        ),
      },
    ),
    builder: _buildTwitterProvider,
  );
}

AuthProvider? _buildTwitterProvider(Map<String, dynamic> config) {
  final enabled =
      parseBoolLike(
        config['enabled'],
        context: 'auth.providers.twitter.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.twitter.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.twitter.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.twitter.redirect_uri',
  );
  final scopes =
      parseStringList(
        config['scopes'],
        context: 'auth.providers.twitter.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultTwitterScopes;

  return twitterProvider(
    TwitterProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes.isEmpty ? _defaultTwitterScopes : scopes,
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

/// Register the Twitter OAuth provider with the registry.
void registerTwitterAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(_twitterRegistration(), overrideExisting: overrideExisting);
}
