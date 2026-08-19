# HTTP/2 Example

Demonstrates how to boot a Routed engine with HTTP/2 enabled including TLS
setup and request handlers that stream responses.

```bash
dart pub get
dart run bin/server.dart
```

Adjust the typed `Http2Config` and TLS paths in `bin/server.dart` for your
local certificates. This is a local playground and is not distributed on
pub.dev.
