# Routed Engine Configuration Example

This example demonstrates various engine configuration capabilities in the routed package.

## Features Demonstrated

### Engine Configuration
- Trailing slash redirects
- Method not allowed handling
- Multipart file handling
- Trusted proxies
- Template engine setup
- Cache manager configuration

### Application Configuration
- Custom config values
- Environment-based configuration
- Route-based configuration access

## Running the Example

1. Start the server:
```bash
dart run bin/server.dart
```

2. In another terminal, run the client:
```bash
dart run bin/client.dart
```

## Configuration Examples

### Engine Settings
```dart
final engine = Engine(
  config: EngineConfig(
    redirectTrailingSlash: true,
    handleMethodNotAllowed: true,
    multipart: MultipartConfig(
      maxFileSize: 10 * 1024 * 1024, // 10MB
      allowedExtensions: {'jpg', 'png', 'pdf'},
    ),
  ),
  configItems: {
    'app.name': 'Example App',
    'app.env': 'development',
  },
  options: [
    withTrustedProxies(['127.0.0.1']),
    withTemplateEngine(templateEngine),
    withCacheManager(cacheManager),
  ],
);
```

## API Endpoints

### GET /config/engine
Returns current engine configuration settings

### GET /config/app
Returns current application configuration

### POST /upload
Tests multipart file upload configuration

### GET /templates/test
Tests template engine configuration

### GET /cached
Tests cache manager configuration

## Response Example

```json
{
  "engine": {
    "redirectTrailingSlash": true,
    "handleMethodNotAllowed": true,
    "multipart": {
      "maxFileSize": 10485760,
      "allowedExtensions": ["jpg", "png", "pdf"]
    }
  },
  "app": {
    "name": "Example App",
    "env": "development"
  }
}
```

## Testing

Test cases demonstrate:
1. Configuration inheritance
2. Option overrides
3. Middleware configuration
4. Template rendering
5. File uploads
6. Caching

### Example Test
```dart
engineTest(
  'configuration test',
  (engine, client) async {
    final response = await client.getJson('/config/engine');
    response
      .assertStatus(200)
      .assertJson((json) {
        json
          .has('redirectTrailingSlash')
          .has('handleMethodNotAllowed');
      });
  },
  engineConfig: EngineConfig(
    redirectTrailingSlash: true,
    handleMethodNotAllowed: true,
  ),
);
```

## Code Structure

- `bin/server.dart`: Server implementation with configuration examples
- `bin/client.dart`: Test client to demonstrate configuration
- `pubspec.yaml`: Project dependencies
- `README.md`: Documentation
