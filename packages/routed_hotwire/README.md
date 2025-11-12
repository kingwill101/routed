# routed_hotwire

[![Pub Version](https://img.shields.io/pub/v/routed_hotwire.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/routed_hotwire)
[![CI](https://github.com/kingwill101/routed/actions/workflows/publish.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/publish.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-❤-ff69b4?logo=github-sponsors)](https://www.buymeacoffee.com/kingwill101)

Turbo/Stimulus helpers for the `routed` framework. The package wires Hotwire
responses, server-rendered stream updates, and Stimulus command helpers into the
Routed engine so you can build interactive hybrids without leaving Dart.

## Features

- Response helpers for Turbo Streams, frames, redirects, and flash messages.
- Stimulus controller scaffolds and middleware to register assets.
- Testing utilities layered on top of `routed_testing` / `server_testing`.
- Example apps showing Hotwire navigation, optimistic updates, and logging.

## Install

```yaml
dependencies:
  routed_hotwire: ^0.1.0
```

Turbo-first apps typically include `routed`, `routed_testing`, and
`server_testing` dev dependencies as well.

## Usage

```dart
import 'package:routed_hotwire/routed_hotwire.dart';

router.post('/notes', (ctx) async {
  final note = await notes.create(ctx.input('content'));
  return turboStream((streams) {
    streams.append('#notes', renderNote(note));
  });
});
```

See the `example/` directory for a runnable Todo app with Turbo navigation and
Stimulus controllers.

## Funding

If this adapter saves you time, consider supporting the work on
[Buy Me a Coffee](https://www.buymeacoffee.com/kingwill101).
