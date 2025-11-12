# OAuth Keycloak Example

Proves out Routed's OAuth flow + Keycloak integration, including token exchange
and middleware guards.

```bash
dart pub get
dart run bin/server.dart --config config/oauth.yaml
```

Refer to the config directory for Keycloak-specific settings.
