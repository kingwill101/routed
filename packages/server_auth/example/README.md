# server_auth example

Demonstrates core auth primitives without framework coupling:

- provider registration and provider factory usage
- JWT issue + verify flow
- gate registration + authorization check

## Run

```bash
dart run example/main.dart
```

## Expected output

```text
provider id = google
jwt subject = user_42
can update post = true
```
