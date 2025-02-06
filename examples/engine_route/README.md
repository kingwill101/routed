# Routed Engine Route Example

This example demonstrates how to work with routes in the Engine, including route matching, parameters, constraints, and URL generation.

## Features Demonstrated

### Route Definition
- Basic route registration
- Route parameters
- Optional parameters
- Wildcard parameters
- Route constraints
- Route naming
- URL generation

### Route Matching
- Exact matches
- Parameter extraction
- Type constraints
- Regular expression constraints
- Domain constraints
- Fallback routes
- Method matching

## Running the Example

1. Start the server:
```bash
dart run bin/server.dart
```

2. In another terminal, run the client:
```bash
dart run bin/client.dart
```

## Code Examples

### Basic Routes
```dart
// Simple route
engine.get('/hello', (ctx) => ctx.string('Hello, World!'));

// Named route with parameters
engine
  .get('/users/{id}', (ctx) => ctx.json({'id': ctx.param('id')}))
  .name('users.show');
```

### Parameter Types
```dart
// Integer parameter
engine.get('/items/{id:int}', (ctx) => ctx.json({'id': ctx.param('id')}));

// Optional parameter
engine.get('/posts/{page?}', (ctx) => ctx.json({'page': ctx.param('page') ?? '1'}));

// Wildcard parameter
engine.get('/files/{*path}', (ctx) => ctx.json({'path': ctx.param('path')}));
```

### Route Constraints
```dart
// Regex constraint
engine.get('/users/{id}', handler, constraints: {
  'id': r'\d+'
});

// Domain constraint
engine.get('/admin', handler, constraints: {
  'domain': r'admin\.example\.com'
});
```

### URL Generation
```dart
// Generate URL from route name
final url = route('users.show', {'id': '123'});
```

## API Endpoints

### GET /hello
Basic route example

### GET /users/{id}
Route with parameter and constraints

### GET /items/{id:int}
Route with typed parameter

### GET /posts/{page?}
Route with optional parameter

### GET /files/{*path}
Route with wildcard parameter

### GET /admin
Route with domain constraint

## Testing

Test cases demonstrate:
1. Route matching behavior
2. Parameter extraction
3. Constraint validation
4. URL generation
5. Fallback routes

### Example Test
```dart
engineTest(
  'route parameter test',
  (engine, client) async {
    final response = await client.getJson('/users/123');
    response
      .assertStatus(200)
      .assertJson((json) {
        json.where('id', '123');
      });
  },
);
```

## Code Structure

- `bin/server.dart`: Server implementation with route examples
- `bin/client.dart`: Test client demonstrating route usage
- `pubspec.yaml`: Project dependencies