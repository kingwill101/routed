# Routed Route Matching Example

This example demonstrates the various route matching capabilities in the routed package.

## Features Demonstrated

### Route Types
- Basic routes
- Parameter routes
- Optional parameters
- Type constraints
- Regular expression constraints
- Domain constraints
- Wildcard routes
- Route groups
- Nested groups
- Fallback routes

## Route Examples

### Basic Route
```dart
engine.get('/hello', handler);
```

### Required Parameter
```dart
engine.get('/users/{id}', handler);
```

### Optional Parameter
```dart
engine.get('/posts/{page?}', handler);
```

### Type Constraint
```dart
engine.get('/items/{id:int}', handler);
```

### Multiple Parameters
```dart
engine.get('/users/{userId}/posts/{postId}', handler);
```

### Regex Constraint
```dart
engine.get('/products/{code}', handler, constraints: {
  'code': r'^[A-Z]{2}\d{3}$'
});
```

### Domain Constraint
```dart
engine.get('/admin', handler, constraints: {
  'domain': r'^admin\.localhost$'
});
```

### Wildcard Route
```dart
engine.get('/files/{*path}', handler);
```

### Route Groups
```dart
engine.group(
  path: '/api/v1',
  builder: (router) {
    router.get('/status', handler);
  }
);
```

## Running the Example

1. Start the server:
```bash
dart run bin/server.dart
```

2. Run the client tests:
```bash
dart run bin/client.dart
```

## Available Routes

- GET /hello
- GET /users/{id}
- GET /posts/{page?}
- GET /items/{id:int}
- GET /users/{userId}/posts/{postId}
- GET /products/{code} (format: XX000)
- GET /admin (requires admin.localhost)
- GET /files/{*path}
- GET /api/v1/status
- GET /api/v1/admin/dashboard

## Code Structure

- `bin/server.dart`: Server implementation with route examples
- `bin/client.dart`: Test client for route matching
- `pubspec.yaml`: Project dependencies