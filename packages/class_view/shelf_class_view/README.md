# shelf_class_view

[![Pub Version](https://img.shields.io/pub/v/shelf_class_view.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/shelf_class_view)
[![CI](https://github.com/kingwill101/routed/actions/workflows/publish.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/publish.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../../LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-❤-ff69b4?logo=github-sponsors)](https://www.buymeacoffee.com/kingwill101)

Shelf adapter for `class_view`. Translate Shelf `Request`/`Response` objects
into the class_view infrastructure so you can author Django-style views and
forms while still deploying on plain Shelf or shelf_router apps.

## Install

```yaml
dependencies:
  class_view: ^0.1.0
  shelf: ^1.4.0
  shelf_router: ^1.1.0
  shelf_class_view: ^1.0.0
```

## Usage

```dart
final router = shelf_router.Router()
  ..get('/hello', shelfClassView(HelloView()));
```

See the README within `class_view/` for form builder docs.

## Funding

[Buy me a coffee](https://www.buymeacoffee.com/kingwill101) if this adapter
saves you time.
