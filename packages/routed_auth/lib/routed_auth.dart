/// OAuth providers for the [routed](https://pub.dev/packages/routed) framework.
///
/// This package provides 13 pre-built OAuth and authentication providers that
/// integrate with the routed auth system. Each provider follows the NextAuth.js
/// pattern for configuration, token exchange, and profile mapping.
///
/// ## Included Providers
///
/// **Social Providers:**
/// - [googleProvider] — Google OAuth with OIDC support, Workspace domain
///   restriction via `hostedDomain`, and configurable `accessType`/`prompt`.
/// - [discordProvider] — Discord OAuth with animated avatar detection and
///   CDN URL construction.
/// - [twitterProvider] — Twitter/X OAuth 2.0 with PKCE. Uses API v2 endpoints.
///   Does **not** return email by default.
/// - [facebookProvider] — Facebook OAuth using Graph API v18.0 with nested
///   picture data extraction.
///
/// **Enterprise Providers:**
/// - [microsoftEntraProvider] — Microsoft Entra ID (Azure AD) with OIDC.
///   Supports single-tenant, multi-tenant, and personal accounts via
///   [MicrosoftEntraTenantType].
/// - [appleProvider] — Apple Sign In with OIDC using `form_post` response mode.
///   User name is only returned on first sign-in. Profile helper: [AppleName].
///
/// **Developer Platforms:**
/// - [gitlabProvider] — GitLab OAuth with **self-hosted** support via `baseUrl`.
/// - [dropboxProvider] — Dropbox OAuth with a custom POST-based
///   `userInfoRequest` callback and configurable `tokenAccessType`.
///
/// **Business/Communication:**
/// - [slackProvider] — Slack OAuth with OIDC. Includes workspace metadata
///   (team ID, name, domain) via custom OIDC claims.
/// - [linkedInProvider] — LinkedIn Sign In v2 with OIDC.
///
/// **Entertainment:**
/// - [spotifyProvider] — Spotify OAuth using the Web API `/v1/me` endpoint.
///   Profile helpers: [SpotifyImage], [SpotifyFollowers].
/// - [twitchProvider] — Twitch OAuth with OIDC. Uses `client_secret_post`
///   (no basic auth).
///
/// **Messaging:**
/// - [telegramProvider] — Telegram Login Widget with HMAC-SHA256 signature
///   verification. Not a standard OAuth flow; uses the [CallbackProvider] mixin.
///   Throws [TelegramAuthException] on invalid or expired auth data.
///   Does **not** return email.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:routed/auth.dart';
/// import 'package:routed_auth/routed_auth.dart';
///
/// final manager = AuthManager(
///   AuthOptions(
///     providers: [
///       googleProvider(GoogleProviderOptions(
///         clientId: env('GOOGLE_CLIENT_ID'),
///         clientSecret: env('GOOGLE_CLIENT_SECRET'),
///         redirectUri: 'https://example.com/auth/callback/google',
///       )),
///       discordProvider(DiscordProviderOptions(
///         clientId: env('DISCORD_CLIENT_ID'),
///         clientSecret: env('DISCORD_CLIENT_SECRET'),
///         redirectUri: 'https://example.com/auth/callback/discord',
///       )),
///     ],
///   ),
/// );
/// ```
///
/// ## Config-Driven Registration
///
/// For config-driven setups, register providers with the
/// [AuthProviderRegistry] and configure them via YAML:
///
/// ```dart
/// import 'package:routed_auth/routed_auth.dart';
///
/// // Register all 13 providers at once
/// registerAllAuthProviders(AuthProviderRegistry.instance);
///
/// // Or register individual providers
/// registerGoogleAuthProvider(AuthProviderRegistry.instance);
/// registerDiscordAuthProvider(AuthProviderRegistry.instance);
/// ```
///
/// Then configure via `config/auth.yaml`:
///
/// ```yaml
/// auth:
///   providers:
///     google:
///       client_id: ${GOOGLE_CLIENT_ID}
///       client_secret: ${GOOGLE_CLIENT_SECRET}
///       redirect_uri: https://example.com/auth/callback/google
/// ```
///
/// ## Custom userInfoRequest
///
/// Some providers (like Dropbox) require non-standard userinfo requests.
/// The [dropboxProvider] demonstrates this pattern with a POST-based endpoint.
///
/// ## Typed Profiles
///
/// Every provider includes a typed profile class with `fromJson`/`toJson`
/// support and an `AuthUser` mapping. For example, [GoogleProfile] provides
/// fields like `email`, `name`, `picture`, and `emailVerified`.
///
/// Helper classes for nested profile data:
/// - [AppleName] — first/last name from Apple Sign In
/// - [FacebookPicture] — picture URL, dimensions, and silhouette flag
/// - [SpotifyImage] — image URL with width/height
/// - [SpotifyFollowers] — follower count
/// - [MicrosoftEntraTenantType] — enum for Entra ID tenant configuration
/// - [TelegramAuthException] — thrown on invalid Telegram auth data
library;

// Provider exports
export 'src/providers/google.dart';
export 'src/providers/discord.dart';
export 'src/providers/microsoft_entra.dart';
export 'src/providers/apple.dart';
export 'src/providers/twitter.dart';
export 'src/providers/facebook.dart';
export 'src/providers/gitlab.dart';
export 'src/providers/spotify.dart';
export 'src/providers/slack.dart';
export 'src/providers/linkedin.dart';
export 'src/providers/twitch.dart';
export 'src/providers/telegram.dart';
export 'src/providers/dropbox.dart';

// Registry
export 'src/registry.dart';
