# jaspr_routed

[![Pub Version](https://img.shields.io/pub/v/jaspr_routed.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/jaspr_routed)
[![CI](https://github.com/kingwill101/routed/actions/workflows/publish.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/publish.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)
[![Sponsor](https://img.shields.io/badge/support-Buy%20Me%20a%20Coffee-ff813f?logo=buymeacoffee)](https://www.buymeacoffee.com/kingwill101)

A bridge between [jaspr](https://github.com/jessecranford/jaspr) components and
the Routed engine. It lets you mount jaspr views inside Routed routes and share
state/configuration between the two worlds without rewriting handlers.

## Features

- `JasprAdapter` that renders jaspr components from Routed route handlers.
- Shared dependency injection so jaspr widgets can access Routed services.
- Example app demonstrating localized templates and streaming updates.

## Install

```yaml
dependencies:
  jaspr_routed: ^0.1.0
  routed: ^0.2.0
  jaspr: ^0.21.0
```

## Usage

```dart
import 'package:jaspr_routed/jaspr_routed.dart';

router.get('/dashboard', (ctx) async {
  return JasprResponse(component: DashboardComponent(data: await ctx.cache('stats')));
});
```

Explore `packages/jaspr_routed/example` for a runnable sample with SSR + hot
reload.

## Funding

Support future Routed/Jaspr adapters by
[buying me a coffee](https://www.buymeacoffee.com/kingwill101).
