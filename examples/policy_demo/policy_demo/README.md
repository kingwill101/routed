# Policy Demo

This project exposes a JSON API using [Routed](https://routed.dev).

## Useful scripts

```bash
dart pub get
```

```
# Run the API locally on port 8080
dart run routed dev
```

### Example requests

```
curl http://localhost:8080/api/v1/health
curl http://localhost:8080/api/v1/users

# Login with a role that can create/update projects
curl -i -c cookies.txt \
  -H "Content-Type: application/json" \
  -d '{"id":"ada","role":"editor"}' \
  http://localhost:8080/api/v1/login

# Policy-protected routes
curl -i -b cookies.txt http://localhost:8080/api/v1/projects
curl -i -b cookies.txt \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"name":"Analytical"}' \
  http://localhost:8080/api/v1/projects
```

Policies are defined in `lib/app.dart` using `Policy` + `PolicyBinding` and are
registered through `AuthOptions` so they are applied by the auth provider. The
routes use `Haigate.authorize` to enforce the policy abilities.

See `lib/app.dart` for the complete route definitions. `test/api_test.dart`
shows how to exercise the engine with `routed_testing`.
