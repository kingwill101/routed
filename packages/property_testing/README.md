# property_testing

[![Pub Version](https://img.shields.io/pub/v/property_testing.svg?label=pub&color=2bb7f6)](https://pub.dev/packages/property_testing)
[![CI](https://github.com/kingwill101/routed/actions/workflows/property_testing.yaml/badge.svg)](https://github.com/kingwill101/routed/actions/workflows/property_testing.yaml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](../../LICENSE)
[![Sponsor](https://img.shields.io/badge/support-Buy%20Me%20a%20Coffee-ff813f?logo=buymeacoffee)](https://www.buymeacoffee.com/kingwill101)

Property-based testing utilities for Dart with shrinking, chaos generators, and
stateful test runners. It powers the Routed ecosystem’s reliability tests but
is framework-agnostic, so you can mix its generators with plain `package:test`
or your own HTTP clients.

## Features

- **Focused generators** for primitives, JSON, URIs, HTTP payloads, and
  state-machine commands.
- **Chaos helpers** that mimic malformed or adversarial payloads to fuzz HTTP
  handlers.
- **Shrinking + reporting** that isolates the smallest failing case with
  concise, colorized reports.
- **Stateful runners** that exercise reducers or domain models with command
  sequences.

## Install

```yaml
dev_dependencies:
  property_testing: ^0.3.0
  test: ^1.26.0
```

> Tip: `dart pub add --dev property_testing` will update your manifest
> automatically.

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

## Chaos payload example

Use the built-in `Chaos` generators to spray malformed data at an endpoint and
assert the server never crashes:

```dart
test('API survives chaotic usernames', () async {
  final client = TestClient(...); // however you talk to your service

  final runner = PropertyTestRunner<String>(
    Chaos.string(minLength: 1, maxLength: 120),
    (userId) async {
      final response = await client.get('/api/users/$userId');
      expect(response.statusCode, lessThan(500));
    },
  );

  final report = await runner.run();
  expect(report.success, isTrue, reason: report.report);
});
```

## Stateful model example

Drive a finite-state machine by generating commands that mutate the in-memory
model and assert invariants after each update:

```dart
class CounterCommand {
  const CounterCommand._(this.apply);
  final int Function(int) apply;

  static final Generator<CounterCommand> gen = Gen.oneOfConst([
    CounterCommand._((value) => value + 1),
    CounterCommand._((value) => value - 1),
    CounterCommand._((value) => value * 2),
  ]);
}

void main() {
  test('counter never dips below -5', () async {
    final runner = StatefulPropertyRunner<int, CounterCommand>(
      commandGen: CounterCommand.gen,
      initialState: () => 0,
      invariant: (value) => value >= -5,
      update: (value, command) => command.apply(value),
      config: const StatefulPropertyConfig(numTests: 100),
    );

    final report = await runner.run();
    expect(report.success, isTrue, reason: report.report);
  });
}
```

## Funding

If this library saves you time, consider
[supporting @kingwill101 on Buy Me a Coffee](https://www.buymeacoffee.com/kingwill101)
to help keep the Routed ecosystem maintained.***
