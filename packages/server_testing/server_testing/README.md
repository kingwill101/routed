# server_testing

[![Pub Version](https://img.shields.io/pub/v/server_testing.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/server_testing)
[![CI](https://github.com/kingwill101/routed/actions/workflows/server_testing.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/server_testing.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../../LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-❤-ff69b4?logo=github-sponsors)](https://www.buymeacoffee.com/kingwill101)

`server_testing` is a batteries-included test harness for Dart HTTP backends. It
packages an expressive HTTP test client, fluent response assertions, browser
automation, request handler adapters, and a CLI for managing browser binaries.

## Highlights

- **First-class HTTP client** – issue requests against any `RequestHandler`
  implementation and assert status, headers, JSON bodies, cookies, and more.
- **Fluent matchers** – `TestResponse` exposes helpers like
  `assertStatus`, `assertJson`, `assertJsonContains`, `assertCookie`, and
  `followRedirects`.
- **Browser testing** – the CLI installs Chrome/Firefox drivers and the browser
  API exposes async & sync flavours with rich assertions.
- **Adapters for any stack** – ship with `IoRequestHandler` for `dart:io`,
  but you can implement the `RequestHandler`/`TestTransport` APIs to connect
  any framework.
- **Fixtures & bundles** – fixture registry, device descriptors, and CLI
  helpers (`server_testing install`, `server_testing devices`, etc.).
- **Extensible** – add custom routers, extend the assertion DSL, or define your
  own transport/server lifecycle hooks.

## Install

```yaml
# pubspec.yaml
dev_dependencies:
  server_testing: ^0.2.0
  test: ^1.26.3
```

```bash
dart pub get
# optional: install browser binaries for integration tests
dart run server_testing install
```

## Quick start

### HTTP testing

```dart
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

Future<void> handler(HttpRequest request) async {
  request.response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.json
    ..write('{"message": "pong"}');
  await request.response.close();
}

void main() {
  serverTest('GET /ping returns pong', (client) async {
    final response = await client.get('/ping');

    response
      .assertStatus(HttpStatus.ok)
      .assertJson((json) {
        json.has('message').where('message', 'pong');
      });
  }, handler: IoRequestHandler(handler));
}
```

### Browser testing

```dart
import 'package:server_testing/browser.dart';
import 'package:server_testing/server_testing.dart';
import 'package:test/test.dart';

void main() {
  browserTest('Login flow', (browser) async {
    await browser.go('/login');
    await browser.type('input[name=email]', 'demo@example.com');
    await browser.type('input[name=password]', 'secret');
    await browser.click('button[type=submit]');

    await browser.expectLocation('/dashboard');
    await browser.expectText('.welcome', contains: 'Welcome back');
  });
}
```

The CLI command `dart run server_testing install` downloads the required
WebDriver binaries and keeps them up to date.

#### Logging controls

Browser bootstrap can generate extensive logs. You can disable them globally
with environment variables:

- `SERVER_TESTING_DISABLE_LOGS=1` disables file creation and console output.
- `SERVER_TESTING_ENABLE_LOGS=1` re-enables logging even if it was disabled
  earlier in the process.

Per-suite control is also available via `BrowserConfig`:

```dart
import 'package:contextual/contextual.dart';

await testBootstrap(
  BrowserConfig(
    browserName: 'chromium',
    loggingEnabled: false,
  ),
);

// You can also attach structured metadata to individual log entries.
final logger = BrowserLogger();
logger.info(
  'Startup complete',
  context: Context({'service': 'dashboard', 'pid': pid}),
);
```

#### Overriding browser executables

If your environment already has Chrome/Firefox installed, you can skip the
auto-downloader by pointing server_testing at existing binaries:

```bash
export SERVER_TESTING_CHROMIUM_BINARY="/usr/bin/google-chrome"
export SERVER_TESTING_FIREFOX_BINARY="/usr/bin/firefox"
```

or directly through `BrowserConfig`:

```dart
await testBootstrap(
  BrowserConfig(
    binaryOverrides: {
      'chromium': '/usr/bin/google-chrome',
      'firefox': '/usr/bin/firefox',
    },
  ),
);
```

When overrides are present the bootstrap is read-only: installation is skipped
but the paths are validated so you'll get a clear failure if a binary is
missing.

## Request handler adapters

Implementing `RequestHandler` lets you wrap any framework:

```dart
class RouterHandler implements RequestHandler {
  RouterHandler(this.router);
  final Router router;

  @override
  Future<void> handleRequest(HttpRequest request) =>
      router.handle(request); // delegate to your framework

  @override
  Future<int> startServer({int port = 0}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(handleRequest);
    return _server!.port;
  }

  @override
  Future<void> close([bool force = true]) => _server?.close(force: force);

  HttpServer? _server;
}
```

Use `serverTest` / `serverGroup` with the handler to reuse setup across tests.

## Assertions cheat-sheet

- `TestResponse.assertStatus(int)` / `assertHeader` / `assertBodyEquals`
- `assertJson((AssertableJson json) { ... })`
- `assertJsonContains(Map<String, Object?>)`
- `assertCookie(String name, {String? value, bool? httpOnly})`
- `assertRedirectsTo(String location)`
- `followRedirects({int? limit})`
- `dump()` for debugging output

For browser tests the `Browser` API covers:

- `go`, `click`, `type`, `select`, `screenshot`, `waitFor`
- Structured assertion helpers: `expectText`, `expectVisible`,
  `expectAttribute`, `expectLocation`
- Page/component base classes for Page Object patterns

## CLI overview

```bash
dart run server_testing install          # download/update browsers
dart run server_testing cache clean      # clear driver cache
dart run server_testing devices list     # inspect available device descriptors
dart run server_testing help             # explorer commands
```

The CLI writes metadata under `.server_testing/` so your tests can pick up the
correct binaries without manual configuration.

## Configuration helpers

- `TestTransport` implementations (`InMemoryTransport`, `IoRequestHandler`)
- Fixture & registry helpers for caching drivers
- Device descriptors (mobile, tablet, desktop) for responsive tests
- Utilities for cookies, multipart builders, WebSocket helpers, and more

## Contributing & support

- Issues & feature requests: <https://github.com/kingwill101/routed/issues>
- Pull requests welcome—please include tests covering new behaviour
- Licensed under MIT (see `LICENSE`)

## Funding

Help keep browsers, drivers, and adapters maintained by
[buying me a coffee](https://www.buymeacoffee.com/kingwill101).
