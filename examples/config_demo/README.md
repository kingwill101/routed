# Typed configuration demo

This small server demonstrates a provider-owned configuration type. The
`MailProvider` validates `MailConfig` before boot, binds a `MailService`, and
the routes read the same configuration through typed lookups.

```bash
dart pub get
dart run bin/server.dart
```

Open `http://127.0.0.1:8080/` or `/configuration` after starting the server.
There are no YAML files, generated config snapshots, or dot-notation lookups
in this example.
