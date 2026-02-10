/// OAuth providers for the [routed](https://pub.dev/packages/routed) framework.
///
/// This package provides 13 pre-built OAuth and authentication providers that
/// integrate with the routed auth system. Each provider follows the NextAuth.js
/// pattern for configuration, token exchange, and profile mapping.
///
/// ## Getting Started
///
/// Add both `routed` and `routed_auth` to your `pubspec.yaml`:
///
/// ```yaml
/// dependencies:
///   routed: ^0.3.3
///   routed_auth: ^0.1.0
/// ```
///
/// Then import and configure your providers:
///
/// ```dart
/// import 'package:routed/auth.dart';
/// import 'package:routed_auth/routed_auth.dart';
///
/// final engine = await Engine.create(
///   providers: [
///     ...Engine.builtins,
///     AuthServiceProvider(
///       AuthOptions(
///         providers: [
///           googleProvider(GoogleProviderOptions(
///             clientId: env('GOOGLE_CLIENT_ID'),
///             clientSecret: env('GOOGLE_CLIENT_SECRET'),
///             redirectUri: 'https://example.com/auth/callback/google',
///           )),
///           discordProvider(DiscordProviderOptions(
///             clientId: env('DISCORD_CLIENT_ID'),
///             clientSecret: env('DISCORD_CLIENT_SECRET'),
///             redirectUri: 'https://example.com/auth/callback/discord',
///           )),
///         ],
///       ),
///     ),
///   ],
/// );
/// ```
///
/// ---
///
/// ## Providers
///
/// ### Google — [googleProvider]
///
/// OIDC provider using Google's OAuth 2.0 endpoints.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [googleProvider] returns `OAuthProvider<GoogleProfile>` |
/// | **Options** | [GoogleProviderOptions] |
/// | **Profile** | [GoogleProfile] — `sub`, `email`, `emailVerified`, `name`, `picture`, `givenName`, `familyName`, `locale`, `hd` |
/// | **Default scopes** | `openid`, `profile`, `email` |
/// | **Callback URL** | `/auth/callback/google` |
/// | **Registration** | [registerGoogleAuthProvider] |
///
/// Extra options: `accessType` (set `'offline'` for refresh tokens),
/// `prompt` (set `'consent'` to force consent screen), and `hostedDomain`
/// to restrict login to a specific Google Workspace domain.
///
/// ### Discord — [discordProvider]
///
/// OAuth 2.0 provider using Discord's API.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [discordProvider] returns `OAuthProvider<DiscordProfile>` |
/// | **Options** | [DiscordProviderOptions] |
/// | **Profile** | [DiscordProfile] — `id`, `username`, `discriminator`, `globalName`, `avatar`, `bot`, `system`, `mfaEnabled`, `banner`, `accentColor`, `locale`, `verified`, `email`, `flags`, `premiumType`, `publicFlags` |
/// | **Default scopes** | `identify`, `email` |
/// | **Callback URL** | `/auth/callback/discord` |
/// | **Registration** | [registerDiscordAuthProvider] |
///
/// [DiscordProfile] includes a computed `avatarUrl` getter that builds the
/// CDN URL and detects animated avatars (prefix `a_` → `.gif`).
///
/// ### Twitter/X — [twitterProvider]
///
/// OAuth 2.0 provider with PKCE using Twitter API v2.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [twitterProvider] returns `OAuthProvider<TwitterProfile>` |
/// | **Options** | [TwitterProviderOptions] |
/// | **Profile** | [TwitterProfile] — `id`, `name`, `username`, `description`, `profileImageUrl`, `location`, `url`, `verified`, `protected`, `createdAt`, `pinnedTweetId` |
/// | **Default scopes** | `users.read`, `tweet.read`, `offline.access` |
/// | **Callback URL** | `/auth/callback/twitter` |
/// | **Registration** | [registerTwitterAuthProvider] |
///
/// Uses PKCE (`usePkce: true`). The API response is unwrapped from a `data`
/// wrapper. Does **not** return email by default — you must enable "Request
/// email from users" in Twitter app permissions.
///
/// ### Facebook — [facebookProvider]
///
/// OAuth 2.0 provider using Facebook Graph API v18.0.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [facebookProvider] returns `OAuthProvider<FacebookProfile>` |
/// | **Options** | [FacebookProviderOptions] |
/// | **Profile** | [FacebookProfile] — `id`, `email`, `name`, `firstName`, `lastName`, `picture` ([FacebookPicture]) |
/// | **Default scopes** | `email`, `public_profile` |
/// | **Callback URL** | `/auth/callback/facebook` |
/// | **Registration** | [registerFacebookAuthProvider] |
///
/// Profile picture is extracted from the nested `picture.data` JSON path.
/// [FacebookPicture] has `url`, `width`, `height`, and `isSilhouette` fields.
///
/// ### Microsoft Entra ID — [microsoftEntraProvider]
///
/// OIDC provider for Azure AD / Microsoft Entra ID.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [microsoftEntraProvider] returns `OAuthProvider<MicrosoftEntraProfile>` |
/// | **Options** | [MicrosoftEntraProviderOptions] |
/// | **Profile** | [MicrosoftEntraProfile] — `sub`, `email`, `name`, `preferredUsername`, `picture`, `givenName`, `familyName`, `oid`, `tid` |
/// | **Default scopes** | `openid`, `profile`, `email` |
/// | **Callback URL** | `/auth/callback/microsoft-entra-id` |
/// | **Registration** | [registerMicrosoftEntraAuthProvider] |
///
/// Supports multi-tenant configurations via [MicrosoftEntraTenantType]:
/// - [MicrosoftEntraTenantType.singleTenant] — requires `tenantId`
/// - [MicrosoftEntraTenantType.multiTenant] — any organization (`organizations`)
/// - [MicrosoftEntraTenantType.multiTenantAndPersonal] — work + personal (`common`)
/// - [MicrosoftEntraTenantType.personalOnly] — personal accounts only (`consumers`)
///
/// Email falls back to `preferredUsername` when `email` is null.
///
/// ### Apple — [appleProvider]
///
/// OIDC provider for Sign in with Apple.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [appleProvider] returns `OAuthProvider<AppleProfile>` |
/// | **Options** | [AppleProviderOptions] |
/// | **Profile** | [AppleProfile] — `sub`, `email`, `emailVerified`, `isPrivateEmail`, `name` ([AppleName]) |
/// | **Default scopes** | `name`, `email` |
/// | **Callback URL** | `/auth/callback/apple` |
/// | **Registration** | [registerAppleAuthProvider] |
///
/// Uses `response_mode: 'form_post'` and `useBasicAuth: false`. The `clientId`
/// is your Services ID (not Bundle ID) and `clientSecret` is a JWT signed with
/// your Apple private key. User name is only returned on the **first sign-in**
/// — you must persist it. Apple may return a private relay email. Apple does
/// **not** provide profile pictures. [AppleName] has `firstName`/`lastName`,
/// and [AppleProfile] has a computed `fullName` getter.
///
/// ### GitLab — [gitlabProvider]
///
/// OAuth 2.0 provider with self-hosted instance support.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [gitlabProvider] returns `OAuthProvider<GitLabProfile>` |
/// | **Options** | [GitLabProviderOptions] |
/// | **Profile** | [GitLabProfile] — `id`, `username`, `email`, `name`, `avatarUrl`, `webUrl`, `state`, `bio`, `location`, `publicEmail`, `websiteUrl`, `organization`, `jobTitle`, `twoFactorEnabled`, `isAdmin`, `createdAt` |
/// | **Default scopes** | `read_user` |
/// | **Callback URL** | `/auth/callback/gitlab` |
/// | **Registration** | [registerGitLabAuthProvider] |
///
/// Pass `baseUrl` to point at a self-hosted GitLab instance (defaults to
/// `https://gitlab.com`). All authorization, token, and userinfo endpoints
/// are constructed relative to the base URL. Email falls back to `publicEmail`,
/// and name falls back to `username`.
///
/// ### Dropbox — [dropboxProvider]
///
/// OAuth 2.0 provider with a custom POST-based userinfo request.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [dropboxProvider] returns `OAuthProvider<DropboxProfile>` |
/// | **Options** | [DropboxProviderOptions] |
/// | **Profile** | [DropboxProfile] — `accountId`, `email`, `emailVerified`, `name`, `profilePhotoUrl`, `disabled`, `country`, `locale`, `isPaired`, `accountType` |
/// | **Default scopes** | `account_info.read` |
/// | **Callback URL** | `/auth/callback/dropbox` |
/// | **Registration** | [registerDropboxAuthProvider] |
///
/// Dropbox's `/2/users/get_current_account` endpoint requires a **POST**
/// request (not GET), so this provider supplies a custom `userInfoRequest`
/// callback. Set `tokenAccessType` to `'offline'` (the default) for refresh
/// tokens. Profile parses nested structures: `name.display_name` and
/// `account_type['.tag']`.
///
/// ### Slack — [slackProvider]
///
/// OIDC provider using Slack's OpenID Connect endpoints.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [slackProvider] returns `OAuthProvider<SlackProfile>` |
/// | **Options** | [SlackProviderOptions] |
/// | **Profile** | [SlackProfile] — `sub`, `email`, `emailVerified`, `name`, `picture`, `givenName`, `familyName`, `locale`, `slackTeamId`, `slackTeamName`, `slackTeamDomain`, `slackTeamImage` |
/// | **Default scopes** | `openid`, `profile`, `email` |
/// | **Callback URL** | `/auth/callback/slack` |
/// | **Registration** | [registerSlackAuthProvider] |
///
/// Workspace metadata (team ID, name, domain, image) is extracted from custom
/// OIDC claims prefixed with `https://slack.com/`.
///
/// ### LinkedIn — [linkedInProvider]
///
/// OIDC provider using Sign In with LinkedIn v2.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [linkedInProvider] returns `OAuthProvider<LinkedInProfile>` |
/// | **Options** | [LinkedInProviderOptions] |
/// | **Profile** | [LinkedInProfile] — `sub`, `email`, `emailVerified`, `name`, `picture`, `givenName`, `familyName`, `locale` |
/// | **Default scopes** | `openid`, `profile`, `email` |
/// | **Callback URL** | `/auth/callback/linkedin` |
/// | **Registration** | [registerLinkedInAuthProvider] |
///
/// Uses the v2 userinfo endpoint at `api.linkedin.com/v2/userinfo`.
/// The legacy v1 API is deprecated.
///
/// ### Spotify — [spotifyProvider]
///
/// OAuth 2.0 provider using the Spotify Web API.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [spotifyProvider] returns `OAuthProvider<SpotifyProfile>` |
/// | **Options** | [SpotifyProviderOptions] |
/// | **Profile** | [SpotifyProfile] — `id`, `displayName`, `email`, `images` (List<[SpotifyImage]>), `country`, `href`, `uri`, `product`, `explicitContent`, `followers` ([SpotifyFollowers]) |
/// | **Default scopes** | `user-read-email` |
/// | **Callback URL** | `/auth/callback/spotify` |
/// | **Registration** | [registerSpotifyAuthProvider] |
///
/// [SpotifyProfile] has a computed `imageUrl` getter (first image URL).
/// [SpotifyImage] provides `url`, `width`, `height`. [SpotifyFollowers]
/// provides `href` and `total`.
///
/// ### Twitch — [twitchProvider]
///
/// OIDC provider using Twitch's `id.twitch.tv` endpoints.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [twitchProvider] returns `OAuthProvider<TwitchProfile>` |
/// | **Options** | [TwitchProviderOptions] |
/// | **Profile** | [TwitchProfile] — `sub`, `email`, `emailVerified`, `preferredUsername`, `picture`, `updatedAt` |
/// | **Default scopes** | `openid`, `user:read:email` |
/// | **Callback URL** | `/auth/callback/twitch` |
/// | **Registration** | [registerTwitchAuthProvider] |
///
/// Uses `client_secret_post` (`useBasicAuth: false`) instead of HTTP Basic
/// auth for token exchange.
///
/// ### Telegram — [telegramProvider]
///
/// Non-OAuth provider using the Telegram Login Widget with HMAC-SHA256
/// signature verification.
///
/// | Item | Detail |
/// |------|--------|
/// | **Factory** | [telegramProvider] returns `TelegramProvider` |
/// | **Options** | [TelegramProviderOptions] |
/// | **Profile** | [TelegramProfile] — `id`, `authDate`, `firstName`, `lastName`, `username`, `photoUrl`, `hash` |
/// | **Callback URL** | `/auth/callback/telegram` |
/// | **Registration** | [registerTelegramAuthProvider] |
///
/// Unlike all other providers, Telegram does **not** use OAuth. Instead,
/// [TelegramProvider] extends `AuthProvider` with the `CallbackProvider` mixin
/// and implements its own `handleCallback()` method. Authentication data
/// is verified with HMAC-SHA256: `secret_key = SHA256(bot_token)`,
/// `hash = HMAC_SHA256(data_check_string, secret_key)`.
///
/// Throws [TelegramAuthException] when the hash is invalid or the `auth_date`
/// exceeds `authDateMaxAge` (default 5 minutes). Does **not** return email.
/// [TelegramProfile] has a computed `fullName` getter.
///
/// Embed the widget in your HTML:
///
/// ```html
/// <script async src="https://telegram.org/js/telegram-widget.js?22"
///   data-telegram-login="YOUR_BOT_USERNAME"
///   data-size="large"
///   data-auth-url="https://example.com/auth/callback/telegram">
/// </script>
/// ```
///
/// ---
///
/// ## Config-Driven Registration
///
/// For config-driven setups, register providers with the `AuthProviderRegistry`
/// and configure them via YAML. Each provider exposes a `register*AuthProvider()`
/// function, or use [registerAllAuthProviders] to register all 13 at once:
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
///       enabled: true
///       client_id: ${GOOGLE_CLIENT_ID}
///       client_secret: ${GOOGLE_CLIENT_SECRET}
///       redirect_uri: https://example.com/auth/callback/google
///       access_type: offline
///       prompt: consent
///     discord:
///       enabled: true
///       client_id: ${DISCORD_CLIENT_ID}
///       client_secret: ${DISCORD_CLIENT_SECRET}
///       redirect_uri: https://example.com/auth/callback/discord
/// ```
///
/// Each provider's config schema supports an `enabled` boolean (default
/// `false`), `client_id`, `client_secret`, `redirect_uri`, and `scopes`.
/// Provider-specific fields are documented in each options class.
///
/// ---
///
/// ## Typed Profiles
///
/// Every provider includes a typed profile class with `fromJson`/`toJson`
/// roundtrip support and a mapping to `AuthUser` via the `profile` callback.
/// The full JSON response is preserved in `AuthUser.attributes`.
///
/// Helper classes for nested profile data:
///
/// - [AppleName] — `firstName`, `lastName` from Apple Sign In
/// - [FacebookPicture] — `url`, `width`, `height`, `isSilhouette`
/// - [SpotifyImage] — `url`, `width`, `height`
/// - [SpotifyFollowers] — `href`, `total`
/// - [MicrosoftEntraTenantType] — enum for Entra ID tenant configuration
/// - [TelegramAuthException] — thrown on invalid or expired Telegram auth data
///
/// ---
///
/// ## Custom userInfoRequest
///
/// Some providers (like Dropbox) require non-standard userinfo requests.
/// The `userInfoRequest` callback on `OAuthProvider` lets you override the
/// default GET-based fetch. See [dropboxProvider] for the POST-based pattern:
///
/// ```dart
/// OAuthProvider<MyProfile>(
///   // ...
///   userInfoRequest: (token, httpClient, endpoint) async {
///     final response = await httpClient.post(
///       endpoint,
///       headers: {
///         'Authorization': 'Bearer ${token.accessToken}',
///         'Content-Type': 'application/json',
///       },
///       body: 'null',
///     );
///     return json.decode(response.body) as Map<String, dynamic>;
///   },
/// );
/// ```
///
/// ---
///
/// ## Provider Feature Matrix
///
/// | Provider | Protocol | PKCE | Email | Self-hosted |
/// |----------|----------|------|-------|-------------|
/// | Google | OIDC | No | Yes | No |
/// | Discord | OAuth 2.0 | No | Yes | No |
/// | Twitter/X | OAuth 2.0 | Yes | No | No |
/// | Facebook | OAuth 2.0 | No | Yes | No |
/// | Microsoft Entra | OIDC | No | Yes | No |
/// | Apple | OIDC | No | Yes | No |
/// | GitLab | OAuth 2.0 | No | Yes | Yes |
/// | Dropbox | OAuth 2.0 | No | Yes | No |
/// | Slack | OIDC | No | Yes | No |
/// | LinkedIn | OIDC | No | Yes | No |
/// | Spotify | OAuth 2.0 | No | Yes | No |
/// | Twitch | OIDC | No | Yes | No |
/// | Telegram | Widget/HMAC | N/A | No | No |
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
