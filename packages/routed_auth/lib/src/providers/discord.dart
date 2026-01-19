import 'package:routed/routed.dart';

/// Discord user profile returned by the userinfo endpoint.
///
/// See [Discord User Object](https://discord.com/developers/docs/resources/user#user-object).
class DiscordProfile {
  const DiscordProfile({
    required this.id,
    required this.username,
    this.discriminator,
    this.globalName,
    this.avatar,
    this.bot,
    this.system,
    this.mfaEnabled,
    this.banner,
    this.accentColor,
    this.locale,
    this.verified,
    this.email,
    this.flags,
    this.premiumType,
    this.publicFlags,
  });

  /// The user's id.
  final String id;

  /// The user's username, not unique across the platform.
  final String username;

  /// The user's Discord-tag (deprecated, will be "0" for new usernames).
  final String? discriminator;

  /// The user's display name, if set.
  final String? globalName;

  /// The user's avatar hash.
  final String? avatar;

  /// Whether the user belongs to an OAuth2 application.
  final bool? bot;

  /// Whether the user is an Official Discord System user.
  final bool? system;

  /// Whether the user has two factor enabled on their account.
  final bool? mfaEnabled;

  /// The user's banner hash.
  final String? banner;

  /// The user's banner color.
  final int? accentColor;

  /// The user's chosen language option.
  final String? locale;

  /// Whether the email on this account has been verified.
  final bool? verified;

  /// The user's email.
  final String? email;

  /// The flags on a user's account.
  final int? flags;

  /// The type of Nitro subscription.
  final int? premiumType;

  /// The public flags on a user's account.
  final int? publicFlags;

  factory DiscordProfile.fromJson(Map<String, dynamic> json) {
    return DiscordProfile(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      discriminator: json['discriminator']?.toString(),
      globalName: json['global_name']?.toString(),
      avatar: json['avatar']?.toString(),
      bot: json['bot'] as bool?,
      system: json['system'] as bool?,
      mfaEnabled: json['mfa_enabled'] as bool?,
      banner: json['banner']?.toString(),
      accentColor: json['accent_color'] as int?,
      locale: json['locale']?.toString(),
      verified: json['verified'] as bool?,
      email: json['email']?.toString(),
      flags: json['flags'] as int?,
      premiumType: json['premium_type'] as int?,
      publicFlags: json['public_flags'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'discriminator': discriminator,
        'global_name': globalName,
        'avatar': avatar,
        'bot': bot,
        'system': system,
        'mfa_enabled': mfaEnabled,
        'banner': banner,
        'accent_color': accentColor,
        'locale': locale,
        'verified': verified,
        'email': email,
        'flags': flags,
        'premium_type': premiumType,
        'public_flags': publicFlags,
      };

  /// Returns the URL for the user's avatar.
  String? get avatarUrl {
    if (avatar == null) return null;
    final ext = avatar!.startsWith('a_') ? 'gif' : 'png';
    return 'https://cdn.discordapp.com/avatars/$id/$avatar.$ext';
  }
}

/// Configuration for the Discord OAuth provider.
///
/// ### Callback URL
/// ```text
/// https://example.com/auth/callback/discord
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
///       discordProvider(
///         DiscordProviderOptions(
///           clientId: env('DISCORD_CLIENT_ID'),
///           clientSecret: env('DISCORD_CLIENT_SECRET'),
///           redirectUri: 'https://example.com/auth/callback/discord',
///         ),
///       ),
///     ],
///   ),
/// );
/// ```
///
/// ### Notes
///
/// - Uses OAuth 2.0 Authorization Code flow.
/// - Default scopes: `identify` and `email`.
/// - Additional scopes: `guilds`, `guilds.join`, `connections`, etc.
class DiscordProviderOptions {
  const DiscordProviderOptions({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    this.scopes = const ['identify', 'email'],
  });

  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final List<String> scopes;
}

/// Discord OAuth provider.
///
/// Based on Discord's OAuth2 documentation.
///
/// ### Resources
/// - https://discord.com/developers/docs/topics/oauth2
/// - https://discord.com/developers/applications
///
/// ### Example
/// ```dart
/// final provider = discordProvider(
///   DiscordProviderOptions(
///     clientId: 'client-id',
///     clientSecret: 'client-secret',
///     redirectUri: 'https://example.com/auth/callback/discord',
///   ),
/// );
/// ```
OAuthProvider<DiscordProfile> discordProvider(DiscordProviderOptions options) {
  return OAuthProvider<DiscordProfile>(
    id: 'discord',
    name: 'Discord',
    clientId: options.clientId,
    clientSecret: options.clientSecret,
    authorizationEndpoint: Uri.parse(
      'https://discord.com/api/oauth2/authorize',
    ),
    tokenEndpoint: Uri.parse('https://discord.com/api/oauth2/token'),
    userInfoEndpoint: Uri.parse('https://discord.com/api/users/@me'),
    redirectUri: options.redirectUri,
    scopes: options.scopes,
    profileParser: DiscordProfile.fromJson,
    profileSerializer: (profile) => profile.toJson(),
    profile: (profile) {
      return AuthUser(
        id: profile.id,
        name: profile.globalName ?? profile.username,
        email: profile.email,
        image: profile.avatarUrl,
        attributes: profile.toJson(),
      );
    },
  );
}

const List<String> _defaultDiscordScopes = ['identify', 'email'];

AuthProviderRegistration _discordRegistration() {
  return AuthProviderRegistration(
    id: 'discord',
    schema: ConfigSchema.object(
      description: 'Discord OAuth provider settings.',
      properties: {
        'enabled': ConfigSchema.boolean(
          description: 'Enable the Discord provider.',
          defaultValue: false,
        ),
        'client_id': ConfigSchema.string(
          description: 'Discord OAuth client ID.',
          defaultValue: "{{ env.DISCORD_CLIENT_ID | default: '' }}",
        ),
        'client_secret': ConfigSchema.string(
          description: 'Discord OAuth client secret.',
          defaultValue: "{{ env.DISCORD_CLIENT_SECRET | default: '' }}",
        ),
        'redirect_uri': ConfigSchema.string(
          description: 'OAuth redirect URI for Discord callbacks.',
          defaultValue: "{{ env.DISCORD_REDIRECT_URI | default: '' }}",
        ),
        'scopes': ConfigSchema.list(
          description: 'OAuth scopes requested from Discord.',
          items: ConfigSchema.string(),
          defaultValue: _defaultDiscordScopes,
        ),
      },
    ),
    builder: _buildDiscordProvider,
  );
}

AuthProvider? _buildDiscordProvider(Map<String, dynamic> config) {
  final enabled = parseBoolLike(
        config['enabled'],
        context: 'auth.providers.discord.enabled',
        throwOnInvalid: true,
      ) ??
      false;
  if (!enabled) return null;

  final clientId = _requireString(
    config['client_id'],
    'auth.providers.discord.client_id',
  );
  final clientSecret = _requireString(
    config['client_secret'],
    'auth.providers.discord.client_secret',
  );
  final redirectUri = _requireString(
    config['redirect_uri'],
    'auth.providers.discord.redirect_uri',
  );
  final scopes = parseStringList(
        config['scopes'],
        context: 'auth.providers.discord.scopes',
        allowEmptyResult: true,
        coerceNonStringEntries: true,
        throwOnInvalid: true,
      ) ??
      _defaultDiscordScopes;

  return discordProvider(
    DiscordProviderOptions(
      clientId: clientId,
      clientSecret: clientSecret,
      redirectUri: redirectUri,
      scopes: scopes.isEmpty ? _defaultDiscordScopes : scopes,
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

/// Register the Discord OAuth provider with the registry.
void registerDiscordAuthProvider(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registry.register(_discordRegistration(), overrideExisting: overrideExisting);
}
