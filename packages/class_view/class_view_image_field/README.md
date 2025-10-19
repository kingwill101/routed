# class_view_image_field

Opt-in image field support for the [`class_view`](../class_view) package.

## Usage

Add the dependency to your `pubspec.yaml` alongside `class_view`:

```yaml
dependencies:
  class_view: ^0.1.0
  class_view_image_field:
    path: ../class_view_image_field
```

Import the extension package once during startup:

```dart
import 'package:class_view/class_view.dart';
import 'package:class_view_image_field/class_view_image_field.dart';

class AvatarForm extends Form {
  AvatarForm()
      : super(
          isBound: false,
          data: const {},
          files: const {},
          fields: {
            'avatar': ImageField(helpText: 'Upload a JPG or PNG image'),
          },
        );
}
```

The library registers itself when imported; no additional wiring is necessary.
