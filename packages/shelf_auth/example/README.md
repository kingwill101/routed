# shelf_auth example

Starts a Shelf server that uses `shelf_auth` middleware and `server_auth`
provider contracts.

Routes:

- `GET /auth/providers`
- `GET /me`

## Run

```bash
dart run example/main.dart
```

Then in another terminal:

```bash
curl -i http://127.0.0.1:8080/auth/providers
curl -i http://127.0.0.1:8080/me
curl -i -H "Authorization: Bearer demo-token" http://127.0.0.1:8080/me
```

Expected behavior:

- `/auth/providers` returns provider metadata.
- `/me` returns `401` without bearer token.
- `/me` returns principal JSON with `demo-token`.
