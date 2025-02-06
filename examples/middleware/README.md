# Routed Middleware Example

This example demonstrates how to use middleware in the routed package.

## Features Demonstrated

### Middleware Types
- Global middleware (applied to all routes)
- Group middleware (applied to route groups)
- Route-specific middleware
- Error handling middleware
- Logging middleware
- Authentication middleware
- Rate limiting middleware

## Running the Example

1. Start the server:
```bash
dart run bin/server.dart
```

2. In another terminal, run the client:
```bash
dart run bin/client.dart
```

## Example Middleware

### Logging Middleware
```dart
Future<void> loggingMiddleware(EngineContext ctx) async {
  final startTime = DateTime.now();
  print('[${ctx.request.method}] ${ctx.request.path} - Started');

  await ctx.next();

  final duration = DateTime.now().difference(startTime);
  print('[${ctx.request.method}] ${ctx.request.path} - ${ctx.response.statusCode} (${duration.inMilliseconds}ms)');
}
```

### Authentication Middleware
```dart
Future<void> authMiddleware(EngineContext ctx) async {
  final token = ctx.requestHeader('Authorization');
  if (token != 'secret-token') {
    return ctx.json({'error': 'Unauthorized'}, statusCode: 401);
  }
  await ctx.next();
}
```

## Code Structure

- `bin/server.dart`: Server implementation with middleware examples
- `bin/client.dart`: Test client demonstrating middleware behavior
- `pubspec.yaml`: Project dependencies
