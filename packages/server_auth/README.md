# server_auth

Framework-agnostic authentication runtime primitives and provider implementations.

Includes built-in providers for Google, Discord, Microsoft Entra, Apple, Twitter/X,
Facebook, GitLab, Slack, Spotify, LinkedIn, Twitch, Dropbox, and Telegram.

## Installation

```yaml
dependencies:
  server_auth: ^0.1.0
```

## Quick Start

```dart
import 'package:server_auth/server_auth.dart';

final registry = AuthProviderRegistry.instance;
registerAllAuthProviders(registry);

final google = googleProvider(
  GoogleProviderOptions(
    clientId: 'google-client-id',
    clientSecret: 'google-client-secret',
    redirectUri: 'https://example.com/auth/callback/google',
  ),
);

final providers = <AuthProvider>[google];
```

Use `providers` with your framework adapter (for example, Routed or Shelf adapters)
to wire callback routes, session handling, and auth lifecycle.

## Config-Driven Registration

```dart
import 'package:server_auth/server_auth.dart';

registerAllAuthProviders(AuthProviderRegistry.instance);
```

Then map framework config into provider options and resolve providers from the
registry by key.

## Typed Profiles

Every OAuth provider includes a typed profile model and serializer/parsers,
so user info mapping can stay type-safe.

## Telegram (Non-OAuth)

Telegram uses widget-based auth with HMAC verification via `telegramProvider`.

## License

MIT
