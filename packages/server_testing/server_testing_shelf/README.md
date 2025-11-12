# server_testing_shelf

Shelf adapter for `server_testing`. It translates between Shelf’s `Request` /
`Response` objects and the test harness’ `RequestHandler` interface so you can
drive Shelf apps with the fluent assertions from `server_testing`.

## Install

```yaml
dev_dependencies:
  server_testing: ^0.2.0
  server_testing_shelf: ^0.2.0
  test: ^1.26.0
```

## Example

```dart
import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

void main() {
  final router = (shelf.Request request) => shelf.Response.ok('ok');

  serverTest('Shelf ping', (client) async {
    final response = await client.get('/ping');
    response.assertStatus(HttpStatus.ok).assertBodyContains('ok');
  }, handler: ShelfRequestHandler(router));
}
```

The adapter supports in-memory and ephemeral-server transports, and the project
includes property-based tests to keep the translation layer aligned with the
core package.***
