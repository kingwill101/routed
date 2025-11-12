# server_testing_shelf

[![Pub Version](https://img.shields.io/pub/v/server_testing_shelf.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/server_testing_shelf)
[![CI](https://github.com/kingwill101/routed/actions/workflows/server_testing_shelf.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/server_testing_shelf.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-❤-ff69b4?logo=github-sponsors)](https://github.com/sponsors/kingwill101)

Shelf adapter for `server_testing`. It translates between Shelf’s `Request` /
`Response` objects and the test harness’ `RequestHandler` interface so you can
drive Shelf apps with the fluent assertions from `server_testing`.

## Highlights

- **Zero-boilerplate adapter** – wrap any `shelf.Handler` with
  `ShelfRequestHandler` and instantly gain the testing DSL.
- **In-memory & real sockets** – reuse all `server_testing` transports (e.g.
  `TestClient.inMemory`, `TransportMode.ephemeralServer`).
- **Property-tested translator** – byte streams are copied chunk-by-chunk to
  avoid double-close issues, and the package includes property coverage for the
  adapter.

## Install

```yaml
dev_dependencies:
  server_testing: ^0.2.0
  server_testing_shelf: ^0.2.1
  test: ^1.26.0
```

## Example

```dart
import 'dart:io';

import 'package:server_testing/server_testing.dart';
import 'package:server_testing_shelf/server_testing_shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

void main() {
  final handler = shelf.Pipeline()
      .addMiddleware(shelf.logRequests())
      .addHandler((request) => shelf.Response.ok('ok'));

  serverTest('Shelf ping', (client) async {
    final response = await client.get('/ping');
    response.assertStatus(HttpStatus.ok).assertBodyContains('ok');
  }, handler: ShelfRequestHandler(handler));
}
```

## Funding

Help keep these adapters maintained by
[sponsoring @kingwill101](https://github.com/sponsors/kingwill101).***
