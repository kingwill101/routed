# Forward Proxy Example

Demonstrates how to use the router as a forward proxy server, forwarding requests to another server.

## Features

- Forward all HTTP methods
- Header forwarding
- Request body forwarding
- Response streaming
- Error handling

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
engine.handle('*', '/{*path}', (ctx) async {
  final path = ctx.param('path') ?? '';
  final targetUrl = 'https://example.com/$path';
  
  // Forward the request
  final proxyRequest = http.Request(
    ctx.request.method,
    Uri.parse(targetUrl),
  );

  // Copy headers and body
  ctx.request.headers.forEach((key, values) {
    proxyRequest.headers[key] = values.join(',');
  });
  
  if (['POST', 'PUT'].contains(ctx.request.method)) {
    proxyRequest.body = await ctx.request.body();
  }

  // Forward response
  final response = await client.send(proxyRequest);
  ctx.status(response.statusCode);
  ctx.string(await response.stream.bytesToString());
});
``` 