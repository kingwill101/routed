# Routed Default Router Example

This example demonstrates how to use the default router in the Engine without explicitly mounting routers.

## Features Demonstrated

### Default Router Usage
- Direct route registration on engine
- Route naming and URL generation
- Route parameters
- Route groups
- Middleware application

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

### Direct Route Registration
```dart
// Routes can be added directly to the engine
engine.get('/users', (ctx) => ctx.json({'message': 'List users'}));
engine.post('/users', (ctx) => ctx.json({'message': 'Create user'}));
```

### Route Groups
```dart
// Groups can be created directly on the engine
engine.group(
  path: '/admin',
  middlewares: [authMiddleware],
  builder: (router) {
    router.get('/stats', (ctx) => ctx.json({'stats': 'data'}));
  },
);
```

### Route Parameters
```dart
engine.get('/users/{id}', (ctx) {
  final id = ctx.param('id');
  return ctx.json({'user_id': id});
});
```

### Named Routes
```dart
engine
  .get('/articles/{slug}', (ctx) => ctx.json({'article': 'data'}))
  .name('articles.show');

// Generate URL using route name
final url = route('articles.show', {'slug': 'hello-world'});
```

## API Endpoints

### GET /users
Returns list of users

### POST /users
Creates a new user

### GET /users/{id}
Returns user by ID

### GET /admin/stats
Returns admin statistics (requires auth)

### GET /articles/{slug}
Returns article by slug

## Testing

Test cases demonstrate:
1. Direct route registration
2. Route parameter handling
3. Route group functionality
4. Middleware application
5. URL generation for named routes

### Example Test
```dart
engineTest(
  'default router test',
  (engine, client) async {
    final response = await client.getJson('/users/123');
    response
      .assertStatus(200)
      .assertJson((json) {
        json.where('user_id', '123');
      });
  },
);
```

## Code Structure

- `bin/server.dart`: Server implementation using default router
- `bin/client.dart`: Test client demonstrating endpoint usage
- `pubspec.yaml`: Project dependencies
