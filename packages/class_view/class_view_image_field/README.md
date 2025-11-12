# class_view_image_field

[![Pub Version](https://img.shields.io/pub/v/class_view_image_field.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/class_view_image_field)
[![CI](https://github.com/kingwill101/routed/actions/workflows/publish.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/publish.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../../LICENSE)
[![Sponsor](https://img.shields.io/badge/sponsor-❤-ff69b4?logo=github-sponsors)](https://www.buymeacoffee.com/kingwill101)

Optional image-field decoder & form widgets for `class_view`. Install this
package when you need the full image upload pipeline (validation, resizing,
metadata extraction) without bloating the core `class_view` library.

## Install

```yaml
dependencies:
  class_view: ^0.1.0
  class_view_image_field: ^0.1.0
```

## Usage

```dart
import 'package:class_view_image_field/class_view_image_field.dart';

class AvatarForm extends FormView {
  @override
  late final fields = [
    ImageField('avatar', maxSizeBytes: 2 * 1024 * 1024),
  ];
}
```

## Funding

Help keep optional field packs maintained by
[buying me a coffee](https://www.buymeacoffee.com/kingwill101).
