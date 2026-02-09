# routed_auth

OAuth providers for [routed](https://pub.dev/packages/routed) - includes Google, Discord, Microsoft, Apple, Twitter, and many more out-of-the-box auth providers.

## Installation

```yaml
dependencies:
  routed: ^0.3.3
  routed_auth: ^0.1.0
```

## Quick Start

```dart
import 'package:routed/routed.dart';
import 'package:routed_auth/routed_auth.dart';

final engine = await Engine.create(
  providers: [
    ...Engine.builtins,
    AuthServiceProvider(
      AuthOptions(
        providers: [
          googleProvider(GoogleProviderOptions(
            clientId: env('GOOGLE_CLIENT_ID'),
            clientSecret: env('GOOGLE_CLIENT_SECRET'),
            redirectUri: 'https://example.com/auth/callback/google',
          )),
          discordProvider(DiscordProviderOptions(
            clientId: env('DISCORD_CLIENT_ID'),
            clientSecret: env('DISCORD_CLIENT_SECRET'),
            redirectUri: 'https://example.com/auth/callback/discord',
          )),
        ],
      ),
    ),
  ],
);
```

## Available Providers

### Social
| Provider | Factory | Options Class |
|----------|---------|---------------|
| Google | `googleProvider()` | `GoogleProviderOptions` |
| Discord | `discordProvider()` | `DiscordProviderOptions` |
| Twitter/X | `twitterProvider()` | `TwitterProviderOptions` |
| Facebook | `facebookProvider()` | `FacebookProviderOptions` |

### Enterprise
| Provider | Factory | Options Class |
|----------|---------|---------------|
| Microsoft Entra | `microsoftEntraProvider()` | `MicrosoftEntraProviderOptions` |
| Apple | `appleProvider()` | `AppleProviderOptions` |

### Developer Platforms
| Provider | Factory | Options Class |
|----------|---------|---------------|
| GitLab | `gitlabProvider()` | `GitLabProviderOptions` |
| Dropbox | `dropboxProvider()` | `DropboxProviderOptions` |

### Business/Communication
| Provider | Factory | Options Class |
|----------|---------|---------------|
| Slack | `slackProvider()` | `SlackProviderOptions` |
| LinkedIn | `linkedInProvider()` | `LinkedInProviderOptions` |

### Entertainment
| Provider | Factory | Options Class |
|----------|---------|---------------|
| Spotify | `spotifyProvider()` | `SpotifyProviderOptions` |
| Twitch | `twitchProvider()` | `TwitchProviderOptions` |

### Messaging
| Provider | Factory | Options Class |
|----------|---------|---------------|
| Telegram | `telegramProvider()` | `TelegramProviderOptions` |

## Typed Profiles

Each provider includes a typed profile class with full field coverage:

```dart
final provider = googleProvider(options);

// Profile is typed as GoogleProfile
final user = provider.profile(googleProfile);

// Access typed fields
print(googleProfile.email);
print(googleProfile.name);
print(googleProfile.picture);
print(googleProfile.emailVerified);
```

## Config-Driven Registration

For config-driven setups, register providers with the registry:

```dart
import 'package:routed_auth/routed_auth.dart';

// Register all providers
registerAllAuthProviders(AuthProviderRegistry.instance);

// Or register individual providers
registerGoogleAuthProvider(AuthProviderRegistry.instance);
registerDiscordAuthProvider(AuthProviderRegistry.instance);
```

Then configure via `config/auth.yaml`:

```yaml
auth:
  providers:
    google:
      client_id: ${GOOGLE_CLIENT_ID}
      client_secret: ${GOOGLE_CLIENT_SECRET}
      redirect_uri: https://example.com/auth/callback/google
    discord:
      client_id: ${DISCORD_CLIENT_ID}
      client_secret: ${DISCORD_CLIENT_SECRET}
      redirect_uri: https://example.com/auth/callback/discord
```

## Custom userInfoRequest

Some providers (like Dropbox) require non-standard userinfo requests. Use the `userInfoRequest` callback:

```dart
OAuthProvider<MyProfile>(
  // ... other fields
  userInfoEndpoint: Uri.parse('https://api.example.com/userinfo'),
  userInfoRequest: (token, httpClient, endpoint) async {
    // Custom POST request instead of GET
    final response = await httpClient.post(
      endpoint,
      headers: {
        'Authorization': 'Bearer ${token.accessToken}',
        'Content-Type': 'application/json',
      },
      body: '{}',
    );
    return json.decode(response.body) as Map<String, dynamic>;
  },
);
```

## Telegram (Non-OAuth)

Telegram uses widget-based authentication with HMAC verification:

```dart
final provider = telegramProvider(TelegramProviderOptions(
  botToken: env('TELEGRAM_BOT_TOKEN'),
  redirectUri: 'https://example.com/auth/callback/telegram',
));

// In your HTML, add the Telegram Login Widget:
// <script src="https://telegram.org/js/telegram-widget.js?22"
//         data-telegram-login="YourBotName"
//         data-size="large"
//         data-auth-url="https://example.com/auth/callback/telegram">
// </script>
```

## License

MIT
