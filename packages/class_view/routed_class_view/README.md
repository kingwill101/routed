# routed_class_view

[![Pub Version](https://img.shields.io/pub/v/routed_class_view.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/routed_class_view)
[![CI](https://github.com/kingwill101/routed/actions/workflows/publish.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/publish.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../../LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-❤-ff69b4?logo=github-sponsors)](https://www.buymeacoffee.com/kingwill101)

Adapter that mounts `class_view` controllers into the Routed engine. It provides
middleware wiring, request context bridges, and helper exports so your views can
read Routed services (sessions, cache, config) without glue code.

## Install

```yaml
dependencies:
  class_view: ^0.1.0
  routed: ^0.2.0
  routed_class_view: ^1.0.0
```

## Usage

```dart
import 'package:routed_class_view/routed_class_view.dart';

router.get('/profile', RoutedClassView(ProfileView()));
```

Check `ADAPTER_REVIEW.md` for architecture notes and the `test/` folder for
adapter coverage.

## Funding

Support Routed adapters via
[Buy Me a Coffee](https://www.buymeacoffee.com/kingwill101).
