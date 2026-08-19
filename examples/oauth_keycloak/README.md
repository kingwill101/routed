# OAuth Keycloak Example

Proves out Routed's OAuth flow + Keycloak integration, including token exchange
and middleware guards.

```bash
dart pub get
KEYCLOAK_BASE_URL=http://localhost:8081 dart run bin/server.dart
```

Set `KEYCLOAK_REALM`, `KEYCLOAK_CLIENT_ID`, and `KEYCLOAK_CLIENT_SECRET` as
needed. The example constructs `JwtOptions` and `OAuthIntrospectionOptions`
directly in Dart.
