# class_view

[![Pub Version](https://img.shields.io/pub/v/class_view.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/class_view)
[![CI](https://github.com/kingwill101/routed/actions/workflows/publish.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/publish.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../../LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-❤-ff69b4?logo=github-sponsors)](https://www.buymeacoffee.com/kingwill101)

Django-style class-based views for Dart web frameworks. `class_view` ships a
controller hierarchy, form helpers, and template-friendly rendering primitives
that plug into Routed, Shelf, or any framework that exposes a handler function.

## Highlights

- `View` / `FormView` base classes with overridable hooks (`before`, `handle`,
  `after`, etc.).
- Form widgets, validation helpers, and automatic template context builders.
- Tooling (`tool/build_templates.dart`) to regenerate built-in form templates
  plus verification scripts used in CI.

## Install

```yaml
dependencies:
  class_view: ^0.1.0
```

Add `class_view_routed` or `shelf_class_view` for framework-specific adapters.

## Usage

```dart
import 'package:class_view/class_view.dart';

class HelloView extends View {
  @override
  Future<Response> handle(ViewContext ctx) async {
    return ctx.render('hello.liquid', {'name': ctx.request.queryParameters['name'] ?? 'friend'});
  }
}
```

See `doc/` for architecture notes and `test/` for coverage of forms, errors,
and rendering behaviors.

## Funding

Sponsor the work on [Buy Me a Coffee](https://www.buymeacoffee.com/kingwill101)
to keep these adapters maintained.
