# OAuth2 + Keycloak Demo

This example spins up Keycloak and a Routed server that validates tokens using both JWT signature
checks and RFC 7662 introspection. It is meant for manual experimentation—no automation here.

## Prerequisites

- Docker / Docker Compose
- `curl`

## Setup

1. Start the stack (opens Keycloak on 8081, Routed on 8080):

   ```bash
   docker compose up --build
   ```

2. Once Keycloak reports `Realm demo imported` (or you import manually via the admin UI), obtain a
   token. Example using client credentials:

   ```bash
   curl -u routed-resource:secret \
     -d 'grant_type=client_credentials&scope=profile' \
     http://localhost:8081/realms/demo/protocol/openid-connect/token
   ```

3. Call Routed with the access token:

   ```bash
   curl -H 'Authorization: Bearer <token>' http://localhost:8080/profile
   ```

## Notes

- Default credentials: `alice` / `password` (for password or auth-code flows).
- Tokens carry `scope=profile` which the server reflects on `/profile`.
- `/call-client-credentials` exchanges a new token using Routed’s internal `OAuth2Client` helper.
