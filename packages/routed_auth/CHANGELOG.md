## 0.1.0

### OAuth Providers

Initial release with pre-built OAuth providers following the NextAuth.js pattern.

**Social Providers:**
- Google OAuth with OIDC support
- Discord OAuth
- Twitter/X OAuth 2.0
- Facebook OAuth

**Enterprise Providers:**
- Microsoft Entra ID (Azure AD)
- Apple Sign In

**Developer Platforms:**
- GitLab OAuth
- Dropbox OAuth (with POST-based userinfo endpoint)

**Business/Communication:**
- Slack OAuth with OIDC
- LinkedIn OAuth

**Entertainment:**
- Spotify OAuth
- Twitch OAuth with OIDC

**Messaging:**
- Telegram Login Widget (HMAC-verified callbacks)

### Features

- Typed profile classes with full field coverage for each provider
- Config-driven registration via `AuthProviderRegistry`
- `registerAllAuthProviders()` for bulk registration
- Individual registration functions (e.g., `registerGoogleAuthProvider()`)
- Dropbox provider demonstrates `userInfoRequest` callback for POST-based endpoints
- Telegram provider demonstrates `CallbackProvider` mixin for non-OAuth flows
