# Routed Route Grouping Example

This example demonstrates how to use route groups in the routed package.

## Features Demonstrated

### Route Groups
- Basic route grouping
- Nested groups
- Group-specific middleware
- API versioning
- Resource grouping
- Parameter inheritance

## Running the Example

1. Start the server:
```bash
dart run bin/server.dart
```

2. Run the client:
```bash
dart run bin/client.dart
```

## Route Group Examples

### Basic Group with Middleware
```dart
engine.group(
  path: '/admin',
  middlewares: [authMiddleware],
  builder: (router) {
    router.get('/dashboard', handler);
    router.get('/users', handler);
  },
);
```

### API Versioning
```dart
engine.group(
  path: '/api',
  builder: (api) {
    api.group(
      path: '/v1',
      builder: (v1) {
        v1.get('/status', handler);
      },
    );
  },
);
```

### Resource Group
```dart
engine.group(
  path: '/posts',
  builder: (posts) {
    posts.get('/', listHandler);
    posts.get('/{id}', detailHandler);
    
    posts.group(
      path: '/{post_id}/comments',
      builder: (comments) {
        comments.get('/', commentsHandler);
      },
    );
  },
);
```

## Available Routes

### Admin Routes (Protected)
- GET /admin/dashboard
- GET /admin/users

### API Routes
- GET /api/v1/status
- GET /api/v2/status

### Resource Routes
- GET /posts
- GET /posts/{id}
- GET /posts/{post_id}/comments

## Code Structure

- `bin/server.dart`: Server implementation with route groups
- `bin/client.dart`: Test client demonstrating routes
- `pubspec.yaml`: Project dependencies