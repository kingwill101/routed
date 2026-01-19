/// OAuth providers for routed.
///
/// This package provides a collection of pre-built OAuth providers that can be
/// easily integrated with the routed auth system. Each provider follows the
/// NextAuth.js pattern for configuration and profile mapping.
///
/// ## Included Providers
///
/// **Social Providers:**
/// - [googleProvider] - Google OAuth with OIDC support
/// - [discordProvider] - Discord OAuth
/// - [twitterProvider] - Twitter/X OAuth 2.0
/// - [facebookProvider] - Facebook OAuth
///
/// **Enterprise Providers:**
/// - [microsoftEntraProvider] - Microsoft Entra ID (Azure AD)
/// - [appleProvider] - Apple Sign In
///
/// **Developer Platforms:**
/// - [gitlabProvider] - GitLab OAuth
///
/// **Business/Communication:**
/// - [slackProvider] - Slack OAuth with OIDC
/// - [linkedInProvider] - LinkedIn OAuth
///
/// **Entertainment:**
/// - [spotifyProvider] - Spotify OAuth
/// - [twitchProvider] - Twitch OAuth with OIDC
///
/// ## Usage
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
/// For config-driven setups, register providers with the registry:
///
/// ```dart
/// import 'package:routed_auth/routed_auth.dart';
///
/// // Register all providers
/// registerAllAuthProviders(AuthProviderRegistry.instance);
///
/// // Or register individual providers
/// registerGoogleAuthProvider(AuthProviderRegistry.instance);
/// registerDiscordAuthProvider(AuthProviderRegistry.instance);
/// ```
library;

// Core exports
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
