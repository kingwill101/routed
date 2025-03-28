# Routed Fallback Route Example

This example demonstrates how to use fallback routes in the routed package for handling unmatched requests.

## Features Demonstrated

### Fallback Routes

- Global fallback handling
- Group-specific fallbacks
- Nested group fallbacks
- Fallbacks with middleware
- Route priority with fallbacks

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

### Global Fallback

```dart
// Catches any unmatched route
engine.fallback((ctx) {
  return ctx.string('Fallback: ${ctx.uri.path}');
});
```

### Nested API Fallbacks

```dart
engine.group(
  path: '/api',
  builder: (api) {
    // General API fallback
    api.fallback((ctx) => ctx.json({
      'error': 'API route not found',
      'scope': 'api',
    }));

    api.group(
      path: '/v1',
      builder: (v1) {
        // V1-specific fallback
        v1.fallback((ctx) => ctx.json({
          'error': 'V1 API route not found',
          'scope': 'v1',
        }));
      },
    );
  },
);
```

### Fallback with Middleware

```dart
engine.group(
  path: '/secured',
  middlewares: [
    (ctx) async {
      print('Middleware executed');
      await ctx.next();
    },
  ],
  builder: (router) {
    router.fallback((ctx) => ctx.json({
      'error': 'Secured route not found',
    }));
  },
);
```

## API Endpoints

### GET /hello

Regular route example

### GET /api/v1/users

Regular API route example

### GET /api/v1/*

Shows V1 API-specific fallback handling

### GET /api/*

Shows general API fallback handling

### GET /secured/*

Shows middleware-enabled fallback handling

### GET /*

Shows global fallback handling

## Response Examples

### V1 API Fallback

```json
{
  "error": "V1 API route not found",
  "scope": "v1",
  "path": "/api/v1/unknown"
}
```

### General API Fallback

```json
{
  "error": "API route not found",
  "scope": "api",
  "path": "/api/unknown"
}
```

### Secured Route Fallback

```json
{
  "error": "Secured route not found",
  "path": "/secured/unknown"
}
```

### Global Fallback

```text
Fallback: /unknown/path
```

## Code Structure

- `bin/server.dart`: Server implementation with fallback examples
- `bin/client.dart`: Test client demonstrating fallbacks
- `pubspec.yaml`: Project dependencies
- `public/`: Directory for static files