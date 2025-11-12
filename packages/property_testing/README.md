# property_testing

Property-based testing utilities for Dart with shrinking, chaos generators, and
stateful test runners. It powers the Routed ecosystem’s reliability tests but
is framework-agnostic, so you can mix its generators with plain `package:test`
or your own HTTP clients.

## Install

```yaml
dev_dependencies:
  property_testing: ^0.2.0
  test: ^1.26.0
```

## Quick start

```dart
import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';

void main() {
  test('string round-trip is stable', () async {
    final runner = PropertyTestRunner<String>(
      Gen.string(minLength: 1, maxLength: 32),
      (value) async {
        expect(value, equals(value.toString()));
      },
    );

    final result = await runner.run();
    expect(result.success, isTrue, reason: result.report);
  });
}
```

Explore `lib/src/generators` for primitives, chaos payloads, and the reusable
stateful runner used in the Routed test suites.***
