# Property Testing for Dart

A property-based testing framework for Dart, inspired by libraries like Hypothesis and ScalaCheck. It enables writing tests that verify properties of your code against a wide range of automatically generated inputs.

## Features

- **Property-Based Test Runner:** `PropertyTestRunner` executes tests against generated inputs and automatically shrinks failing cases to minimal examples.
- **Powerful Generator Composition:** Build complex data generators from simpler ones using combinators like `map`, `flatMap`, `where`, `list`, `tupleN`, etc.
- **Rich Generator Library:**
    - **Primitives (`Gen`):** Integers, doubles, booleans, strings, lists, sets, maps, tuples, etc.
    - **Specialized (`Specialized`):** `DateTime`, `Duration`, `Uri`, `Color`, email addresses, semantic versions.
    - **Chaos (`Chaos`):** Strings, ints, JSON, bytes designed to find edge cases and security vulnerabilities (SQLi, XSS, etc.). Configurable via `ChaosConfig`.
- **Tree-Based Shrinking:** Efficiently finds minimal failing test cases.
# Property Testing for Dart

A property-based testing framework for Dart, inspired by libraries like Hypothesis and ScalaCheck. It enables writing tests that verify properties of your code against a wide range of automatically generated inputs.

## Features

- **Property-Based Test Runner:** `PropertyTestRunner` executes tests against generated inputs and automatically shrinks failing cases to minimal examples.
- **Powerful Generator Composition:** Build complex data generators from simpler ones using combinators like `map`, `flatMap`, `where`, `list`, `tupleN`, etc.
- **Rich Generator Library:**
    - **Primitives (`Gen`):** Integers, doubles, booleans, strings, lists, sets, maps, tuples, etc.
    - **Specialized (`Specialized`):** `DateTime`, `Duration`, `Uri`, `Color`, email addresses, semantic versions.
    - **Chaos (`Chaos`):** Strings, ints, JSON, bytes designed to find edge cases and security vulnerabilities (SQLi, XSS, etc.). Configurable via `ChaosConfig`.
- **Tree-Based Shrinking:** Efficiently finds minimal failing test cases.
- **Stateful Testing:** Model system behavior over sequences of commands/operations (`StatefulPropertyBuilder`, `StatefulPropertyRunner`).
- **Reproducibility:** Control test runs using `Random` seeds via `PropertyConfig`. Seeds are reported on failure.
- **Detailed Reporting:** Clear reports for failing tests, including original and shrunk inputs, error, stack trace, and shrink path (optional).

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dev_dependencies:
  property_testing: ^0.1.0 # Or the latest version
```

## Usage

### Basic Property Test

Test that a property holds true for generated inputs.

```dart
import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';
import 'dart:math';

void main() {
  test('List reversal property', () async {
    // Generator for lists of integers
    final listGen = Gen.integer(min: 0, max: 100).list(maxLength: 50);

    // Property: Reversing a list twice yields the original list
    final runner = PropertyTestRunner(
      listGen,
      (list) {
        expect(list.reversed.toList().reversed.toList(), equals(list));
      },
      PropertyConfig(numTests: 200, seed: 123), // Use a seed for reproducibility
    );

    final result = await runner.run();
    expect(result.success, isTrue, reason: result.report); // report provides details on failure
  });

  test('Addition is commutative', () async {
    // Generator for pairs (tuples) of integers
    final pairGen = Gen.tuple2(Gen.integer(), Gen.integer());

    final runner = PropertyTestRunner(
      pairGen,
      (pair) {
        expect(pair.$1 + pair.$2, equals(pair.$2 + pair.$1));
      },
      PropertyConfig(numTests: 500),
    );

    final result = await runner.run();
    expect(result.success, isTrue, reason: result.report);
  });
}
```

### Generator Composition

Build generators for complex data structures.

```dart
class User {
  final String id;
  final String email;
  final int age;
  User({required this.id, required this.email, required this.age});
  @override String toString() => 'User(id: $id, email: $email, age: $age)';
}

void main() {
  test('Generate User objects', () async {
    final userGen = Gen.tuple3(
      Gen.string(minLength: 8, maxLength: 8).map((s) => 'user_$s'), // ID
      Specialized.email(domains: ['work.com']), // Email
      Gen.integer(min: 18, max: 65) // Age
    ).map((tuple) => User(id: tuple.$1, email: tuple.$2, age: tuple.$3));

    final runner = PropertyTestRunner(
      userGen,
      (user) {
        expect(user.id, startsWith('user_'));
        expect(user.email, endsWith('@work.com'));
        expect(user.age, inInclusiveRange(18, 65));
      },
    );
    final result = await runner.run();
    expect(result.success, isTrue, reason: result.report);
  });
}
```

### Chaos Testing

Test how your system handles potentially malicious or malformed inputs.

```dart
import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';
// Assume 'client' is a configured HTTP test client (e.g., from server_testing)

void main() {
  test('API search handles chaotic inputs', () async {
    final runner = PropertyTestRunner(
      Chaos.string(maxLength: 200), // Generates chaotic strings
      (input) async {
        // Example: Test an API endpoint
        // final response = await client.get('/api/search?q=$input');
        // Property: API should never crash (5xx error)
        // expect(response.statusCode, lessThan(500));

        // Placeholder assertion for example
        expect(input.length, greaterThanOrEqualTo(0));
      },
      PropertyConfig(numTests: 500),
    );

    final result = await runner.run();
    expect(result.success, isTrue, reason: result.report);
  });
}
```

### Stateful Testing

Verify properties that involve a sequence of operations or state changes. See the `example/stateful_testing` directory for detailed examples using `StatefulPropertyBuilder` and `StatefulPropertyRunner`.

## Advanced Usage

Check the `example/` directory for more advanced usage examples, including:
- Combining various generators (`composition_example.dart`)
- Demonstrating shrinking behavior (`improved_shrinking_example.dart`)
- Using specialized generators (`specialized_generators_example.dart`)
- Testing stateful systems (`stateful_testing/`)
- API testing scenarios (`api_chaos_test.dart`, `api_test.dart`)

## Contributing

Contributions are welcome! Please feel free to submit Issues or Pull Requests.
  @override String toString() => 'User(id: $id, email: $email, age: $age)';
}

void main() {
  test('Generate User objects', () async {
    final userGen = Gen.tuple3(
      Gen.string(minLength: 8, maxLength: 8).map((s) => 'user_$s'), // ID
      Specialized.email(domains: ['work.com']), // Email
      Gen.integer(min: 18, max: 65) // Age
    ).map((tuple) => User(id: tuple.$1, email: tuple.$2, age: tuple.$3));

    final runner = PropertyTestRunner(
      userGen,
      (user) {
        expect(user.id, startsWith('user_'));
        expect(user.email, endsWith('@work.com'));
        expect(user.age, inInclusiveRange(18, 65));
      },
    );
    final result = await runner.run();
    expect(result.success, isTrue, reason: result.report);
  });
}
```

### Chaos Testing

Test how your system handles potentially malicious or malformed inputs.

```dart
import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';
// Assume 'client' is a configured HTTP test client (e.g., from server_testing)

void main() {
  test('API search handles chaotic inputs', () async {
    final runner = PropertyTestRunner(
      Chaos.string(maxLength: 200), // Generates chaotic strings
      (input) async {
        // Example: Test an API endpoint
        // final response = await client.get('/api/search?q=$input');
        // Property: API should never crash (5xx error)
        // expect(response.statusCode, lessThan(500));

        // Placeholder assertion for example
        expect(input.length, greaterThanOrEqualTo(0));
      },
      PropertyConfig(numTests: 500),
    );

    final result = await runner.run();
    expect(result.success, isTrue, reason: result.report);
  });
}
```

### Stateful Testing

Verify properties that involve a sequence of operations or state changes. See the `example/stateful_testing` directory for detailed examples using `StatefulPropertyBuilder` and `StatefulPropertyRunner`.

## Advanced Usage

Check the `example/` directory for more advanced usage examples, including:
- Combining various generators (`composition_example.dart`)
- Demonstrating shrinking behavior (`improved_shrinking_example.dart`)
- Using specialized generators (`specialized_generators_example.dart`)
- Testing stateful systems (`stateful_testing/`)
- API testing scenarios (`api_chaos_test.dart`, `api_test.dart`)

## Contributing

Contributions are welcome! Please feel free to submit Issues or Pull Requests.
