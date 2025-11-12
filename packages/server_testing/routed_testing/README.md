# routed_testing

Routed-specific helpers built on top of `server_testing`. It wires the Routed
engine into the transport abstractions so you can issue HTTP requests against an
in-memory engine or launch an ephemeral server without writing glue code.

## Install

```yaml
dev_dependencies:
  routed_testing: ^0.2.0
  server_testing: ^0.2.0
  routed: ^0.2.0
  test: ^1.26.0
```

## Usage

```dart
import 'package:routed/routed.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:test/test.dart';

void main() {
  test('GET /ping', () async {
    final engine = Engine()..get('/ping', (ctx) => ctx.text('pong'));
    await engine.initialize();
    final handler = RoutedRequestHandler(engine);

    final client = TestClient.inMemory(handler);
    final response = await client.get('/ping');
    response.assertStatus(HttpStatus.ok).assertBodyContains('pong');

    await client.close();
    await handler.close();
    await engine.close();
  });
}
```

See `test/` for more patterns, including property-based coverage of route
parameters across transports.***
