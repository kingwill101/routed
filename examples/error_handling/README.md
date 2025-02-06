# Routed Error Handling Example

This example demonstrates how error handling works in the routed package, including both built-in error handling and custom error types.

## Features Demonstrated

### Error Types
- ValidationError
- EngineError
- Custom Error Types
- Uncaught Exceptions

### Error Handling Features
- Global error catching
- Error type detection
- Status code mapping
- Custom error responses
- Stack trace logging

## Running the Example

1. Start the server:
```bash
dart run bin/server.dart
```

2. In another terminal, run the client:
```bash
dart run bin/client.dart
```

## Error Examples

### Validation Error
```dart
// Returns 422 with validation errors
throw ValidationError({
  'email': ['Invalid email format'],
  'password': ['Too short']
});
```

### Engine Error
```dart
// Returns custom status code with message
throw EngineError(
  message: 'Resource not found',
  code: HttpStatus.notFound
);
```

### Custom Error
```dart
// Maps to specific HTTP response
class ResourceError implements EngineError {
  @override
  final int code = HttpStatus.conflict;
  @override
  final String message = 'Resource already exists';
}
```

### Uncaught Exception
```dart
// Returns 500 Internal Server Error
throw Exception('Unexpected error');
```

## API Endpoints

### GET /validation-error
Demonstrates validation error handling

### GET /engine-error
Demonstrates engine error handling

### GET /custom-error
Demonstrates custom error type handling

### GET /uncaught-error
Demonstrates uncaught exception handling

### POST /users
Demonstrates form validation errors

## Error Responses

### Validation Error (422)
```json
{
  "email": ["Invalid email format"],
  "password": ["Too short"]
}
```

### Engine Error (Custom Code)
```text
EngineError(404): Resource not found
```

### Internal Server Error (500)
```text
An unexpected error occurred. Please try again later.
```

## Code Structure

- `bin/server.dart`: Server implementation with error examples
- `bin/client.dart`: Test client demonstrating error handling
- `pubspec.yaml`: Project dependencies