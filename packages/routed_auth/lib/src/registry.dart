import 'package:routed/auth.dart';

import 'providers/apple.dart';
import 'providers/discord.dart';
import 'providers/dropbox.dart';
import 'providers/facebook.dart';
import 'providers/gitlab.dart';
import 'providers/google.dart';
import 'providers/linkedin.dart';
import 'providers/microsoft_entra.dart';
import 'providers/slack.dart';
import 'providers/spotify.dart';
import 'providers/twitch.dart';
import 'providers/twitter.dart';
import 'providers/telegram.dart';

/// Registers all built-in OAuth providers with the given [registry].
///
/// This provides a convenient way to register all available providers at once.
/// Providers are only instantiated when enabled via configuration.
///
/// ### Example
/// ```dart
/// import 'package:routed/auth.dart';
/// import 'package:routed_auth/routed_auth.dart';
///
/// final registry = AuthProviderRegistry.defaultRegistry;
/// registerAllAuthProviders(registry);
///
/// // Now all providers are available for config-driven registration.
/// ```
///
/// ### Providers included:
/// - Google (OIDC)
/// - Discord
/// - Microsoft Entra ID (Azure AD)
/// - Apple Sign In
/// - Twitter/X
/// - Facebook
/// - GitLab (supports self-hosted)
/// - Spotify
/// - Slack (OIDC)
/// - LinkedIn (OIDC)
/// - Twitch (OIDC)
/// - Telegram (Login Widget)
/// - Dropbox
void registerAllAuthProviders(
  AuthProviderRegistry registry, {
  bool overrideExisting = true,
}) {
  registerGoogleAuthProvider(registry, overrideExisting: overrideExisting);
  registerDiscordAuthProvider(registry, overrideExisting: overrideExisting);
  registerMicrosoftEntraAuthProvider(
    registry,
    overrideExisting: overrideExisting,
  );
  registerAppleAuthProvider(registry, overrideExisting: overrideExisting);
  registerTwitterAuthProvider(registry, overrideExisting: overrideExisting);
  registerFacebookAuthProvider(registry, overrideExisting: overrideExisting);
  registerGitLabAuthProvider(registry, overrideExisting: overrideExisting);
  registerSpotifyAuthProvider(registry, overrideExisting: overrideExisting);
  registerSlackAuthProvider(registry, overrideExisting: overrideExisting);
  registerLinkedInAuthProvider(registry, overrideExisting: overrideExisting);
  registerTwitchAuthProvider(registry, overrideExisting: overrideExisting);
  registerTelegramAuthProvider(registry, overrideExisting: overrideExisting);
  registerDropboxAuthProvider(registry, overrideExisting: overrideExisting);
}
