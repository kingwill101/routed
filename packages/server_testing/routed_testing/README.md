# routed_testing

[![Pub Version](https://img.shields.io/pub/v/routed_testing.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/routed_testing)
[![CI](https://github.com/kingwill101/routed/actions/workflows/routed_testing.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/routed_testing.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../../LICENSE)
[![Sponsor](https://img.shields.io/badge/support-Buy%20Me%20a%20Coffee-ff813f?logo=buymeacoffee)](https://www.buymeacoffee.com/kingwill101)

Routed-specific helpers built on top of `server_testing`. It wires the Routed
engine into the transport abstractions so you can issue HTTP requests against an
in-memory engine or launch an ephemeral server without writing glue code.

## Features

- **Drop-in RequestHandler** – `RoutedRequestHandler` bootstraps an `Engine` and
  connects it to the testing transports.
- **In-memory & real sockets** – flip between `TransportMode.inMemory` and
  `TransportMode.ephemeralServer` without changing your test body.
- **Property helpers** – reuse `TestClient` with `property_testing` to stress
  routing, params, or middleware stacks.

## Install

```yaml
dev_dependencies:
  routed_testing: ^0.3.3
  server_testing: ">=0.4.0 <1.0.0"
  routed_core: ">=0.3.3 <1.0.0"
  test: ^1.29.0
```

> `dart pub add --dev routed_testing server_testing routed_core` will update your
> pubspec automatically.

## Usage

```dart
import 'dart:io';

import 'package:routed_core/routed_core.dart';
import 'package:routed_testing/routed_testing.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

void main() {
  test('GET /ping', () async {
    final engine = await Engine.create();
    engine.get('/ping', (ctx) => ctx.text('pong'));
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

`Engine.create()` in this example initializes the core provider set. If the
application uses feature providers, construct the test engine with the same
provider list as production, or import `package:routed/routed.dart` and use
its batteries-included `Engine.create()` setup.

See `test/` for more patterns, including property-based coverage of route
parameters across transports.

## Funding

Help sustain the Routed ecosystem by
[supporting @kingwill101 on Buy Me a Coffee](https://www.buymeacoffee.com/kingwill101).***
