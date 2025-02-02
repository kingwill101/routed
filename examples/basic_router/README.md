# Basic Router Example

Demonstrates basic routing functionality including path parameters, query strings, and request body handling.

## Features

- Basic GET/POST routes
- Path parameters (`/users/{id}`)
- Query parameters
- JSON request/response handling
- Route grouping

## Running

```bash
dart run bin/server.dart
```

Then in another terminal:
```bash
dart run bin/client.dart
```

## Code Highlights

```dart
// Path parameters
router.get('/users/{id}', (ctx) {
  final id = ctx.param('id');
  ctx.json({'message': 'Got user', 'id': id});
});

// Query parameters
router.get('/search', (ctx) {
  final query = ctx.query('q');
  final page = ctx.defaultQuery('page', '1');
  ctx.json({'query': query, 'page': page});
});

// Route groups
router.group(
  path: '/api',
  builder: (group) {
    group.get('/status', (ctx) {
      ctx.json({'status': 'ok'});
    });
  },
);
``` 