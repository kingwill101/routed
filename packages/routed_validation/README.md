# routed_validation

Validation rules and route-facing validation primitives for the Routed
ecosystem. This package does not register an `Engine` service provider; the
registry is created on demand from an initialized engine container.

## Install
```yaml
dependencies:
  routed: ^0.5.0
  routed_validation: ^0.1.0
```

## Use validation in a Routed app

```dart
import 'package:routed/routed.dart';
import 'package:routed_validation/routed_validation.dart';

Future<void> main() async {
  registerRoutedProviders();
  final engine = await Engine.create();

  engine.post('/users', (ctx) async {
    final input = {
      'email': ctx.query('email'),
      'name': ctx.query('name'),
    };
    final validator = Validator.make(
      {'email': 'required|email', 'name': 'required|min_length:2'},
      registry: requireValidationRegistry(ctx.container),
    );
    final errors = validator.validate(input);
    return errors.isEmpty
        ? ctx.json({'ok': true})
        : ctx.json({'errors': errors}, statusCode: 422);
  });

  await engine.serve(port: 8080);
}
```

There is no separate validation-provider initialization step. Call
`registerRoutedProviders()` when using `package:routed/routed.dart` for the
standard provider bundle, or initialize `Engine.defaultProviders` yourself
with `routed_core`.
