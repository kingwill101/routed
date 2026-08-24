/// Framework-agnostic authentication APIs, including sessions, tokens, and
/// identity providers.
///
/// Import this library to configure authentication runtimes or use the
/// session, authorization, and provider abstractions re-exported from it.
library;

export 'src/core/core.dart';
export 'src/providers/apple.dart';
export 'src/providers/discord.dart';
export 'src/providers/dropbox.dart';
export 'src/providers/facebook.dart';
export 'src/providers/gitlab.dart';
export 'src/providers/github.dart';
export 'src/providers/google.dart';
export 'src/providers/linkedin.dart';
export 'src/providers/microsoft_entra.dart';
export 'src/providers/slack.dart';
export 'src/providers/spotify.dart';
export 'src/providers/telegram.dart';
export 'src/providers/twitch.dart';
export 'src/providers/twitter.dart';
