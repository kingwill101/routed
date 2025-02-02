
# routed_testing

A testing utility package that provides fluent assertions for JSON and HTTP responses. While built for testing the `routed` package, its core utilities can be used independently in any Dart project.

## Features

### Core Utilities (Framework Independent)
- 🔍 Fluent JSON assertions (`AssertableJson`)
- 📝 JSON string validation (`AssertableJsonString`)
- 🔢 Type-safe numeric comparisons
- 📊 Array and object validation
- 🎯 Pattern matching and schema validation

### Routed Integration
- 🌐 HTTP request/response testing
- 🔄 Route testing utilities
- 📦 Multipart request handling
- 🧪 Integration test helpers

## Installation

Add to your `pubspec.yaml`:

```yaml
dev_dependencies:
  routed_testing:
    path: path_to_package/routed_testing
  test: ^1.25.0
```

## Usage

### JSON Assertions

The `AssertableJson` class provides a fluent API for making assertions on JSON data:

#### Basic Usage

```dart
import 'package:routed_testing/routed_testing.dart';

void main() {
  final json = AssertableJson({
    'name': 'John',
    'age': 30,
    'scores': [85, 90, 95]
  });

  json
    .has('name')
    .whereType<String>('name')
    .where('name', 'John')
    .has('age')
    .isGreaterThan('age', 25)
    .count('scores', 3);
}
```

#### Nested Objects

```dart
final json = AssertableJson({
  'user': {
    'profile': {
      'email': 'john@example.com'
    }
  }
});

json.hasNested('user.profile.email');
```

#### Conditional Testing

```dart
json.when(isAdmin, (json) {
  json.has('adminPrivileges');
});
```

#### Array Validation

```dart
json.has('items', 3, (items) {
  items.each((item) {
    item.has('id').has('name');
  });
});
```

#### Numeric Assertions

```dart
json
  .isGreaterThan('age', 18)
  .isLessThan('score', 100)
  .isBetween('rating', 1, 5);
```

#### Pattern Matching

```dart
json
  .whereType<String>('email')
  .whereContains('email', '@')
  .whereIn('status', ['active', 'pending']);
```

#### Schema Validation

```dart
json.matchesSchema({
  'id': int,
  'name': String,
  'active': bool
});
```

#### Property Interaction Tracking

```dart
json
  .has('name')
  .has('age')
  .verifyInteracted(); // Fails if any properties weren't checked
```

### Testing Routes with Test Client

The `EngineTestClient` class allows you to send HTTP requests to your routes and assert the responses:

#### Basic Route Testing

```dart
import 'package:routed_testing/routed_testing.dart';
import 'package:test/test.dart';

void main() {
  engineTest('GET /hello returns a greeting message', (client) async {
    final response = await client.get('/hello');

    response
      .assertStatus(200)
      .assertJson((json) {
        json
          .has('message')
          .where('message', 'Hello, world!');
      });
  });
}
```

#### Multipart Requests

```dart
engineTest('POST /upload handles file upload', (client) async {
  final response = await client.multipart('/upload', (builder) {
    builder.addField('description', 'Test file');
    builder.addFileFromBytes(
      name: 'file',
      bytes: [1, 2, 3, 4, 5],
      filename: 'test.txt',
      contentType: MediaType('text', 'plain'),
    );
  });

  response
    .assertStatus(200)
    .assertJson((json) {
      json
        .has('success')
        .where('success', true);
    });
});
```

## Core Assertion Classes

### AssertableJson

Provides fluent assertions for JSON objects:
- Type checking
- Nested property access
- Array validation
- Numeric comparisons
- Pattern matching
- Schema validation

### AssertableJsonString

Specialized for JSON string validation:
- JSON syntax validation
- Property existence
- Value comparison
- Format validation

## Contributing

The assertion utilities are designed to be extensible. Feel free to contribute additional assertion methods or improvements to the existing ones.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Additional information

TODO: Tell users more about the package: where to find more information, how to 
contribute to the package, how to file issues, what response they can expect 
from the package authors, and more.
