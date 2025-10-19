# Engine Documentation

The `engine` directory contains the core HTTP request processing engine for the Routed framework. This document provides
an overview of the architecture and key components.

## Overview

The Engine is the central orchestrator for all HTTP request handling in Routed. It manages:

- **Routing**: Matching incoming requests to registered routes
- **Middleware**: Executing middleware pipelines
- **Static Files**: Serving static assets
- **WebSockets**: Handling WebSocket connections
- **Configuration**: Managing application settings
- **Service Providers**: Extensible architecture through providers
- **HTTP/2**: Optional HTTP/2 protocol support
- **Graceful Shutdown**: Handling termination signals

## Directory Structure

```
engine/
├── engine.dart              # Main Engine class
├── engine_route.dart        # Compiled route representation
├── engine_routing.dart      # Routing convenience methods
├── engine_opt.dart          # Configuration option functions
├── config.dart              # Configuration classes
├── middleware_registry.dart # Middleware registration and resolution
├── route_match.dart         # Route matching result
├── wrapped_request.dart     # Request body size limiting
├── provider_manifest.dart   # Provider configuration loading
├── mount.dart               # Router mounting structures
├── patterns.dart            # Route parameter patterns
├── param_utils.dart         # Parameter extraction utilities
├── error_handling.dart      # Error handling registry
├── request.dart             # Request handling logic
├── http2_server.dart        # HTTP/2 server implementation
├── engine_template.dart     # View engine integration
├── events/                  # Event system
│   ├── config.dart
│   └── route.dart
└── providers/               # Built-in service providers
    ├── core.dart
    ├── logging.dart
    ├── routing.dart
    └── registry.dart
```

## Core Components

### Engine (`engine.dart`)

The main `Engine` class is the heart of the framework. It:

- Manages multiple mounted routers
- Builds a flattened route table for efficient matching
- Processes incoming HTTP requests through middleware pipelines
- Handles errors and fallback routes
- Integrates with the dependency injection container

**Key Methods:**

- `Engine()` - Constructor with comprehensive configuration options
- `get()`, `post()`, `put()`, `delete()`, etc. - HTTP method route registration
- `use()` - Mount a router at a path prefix
- `route()` - Generate URLs for named routes
- `listen()` - Start the HTTP server
- `close()` - Gracefully shutdown the server

**Example:**

```dart
final engine = Engine(
  config: EngineConfig(
    security: EngineSecurityFeatures(
      maxRequestSize: 10 * 1024 * 1024,
      cors: CorsConfig(enabled: true),
    ),
  ),
  options: [
    withTrustedProxies(['192.168.1.1']),
    withLogging(enabled: true),
  ],
);

engine.get('/users/:id', (req) {
  final id = req.params.require<int>('id');
  return Response.ok('User $id');
});

await engine.listen();
```

### EngineRoute (`engine_route.dart`)

Represents a compiled route with:

- HTTP method and path pattern
- Compiled regex for URL matching
- Parameter type information
- Middleware stack
- Route constraints
- Handler function

**Features:**

- **Parameter Extraction**: Extracts typed parameters from URLs
- **Custom Casting**: Register custom type converters for route parameters
- **Constraint Validation**: Validate routes against custom rules
- **Pattern Matching**: Efficient regex-based URL matching

**Example:**

```dart
// Register custom type casting
EngineRoute.registerCustomCasting('slug', (value) {
  return value?.toLowerCase().replaceAll('_', '-');
});

// Route with typed parameters
engine.get('/posts/:id:int/comments/:slug:slug', handler);
```

### Configuration (`config.dart`)

Comprehensive configuration system with classes for:

- **EngineConfig**: Main configuration container
- **EngineSecurityFeatures**: Security headers, CSRF, max request size
- **CorsConfig**: Cross-origin resource sharing settings
- **MultipartConfig**: File upload limits and permissions
- **Http2Config**: HTTP/2 protocol settings
- **ViewConfig**: Template engine configuration
- **SessionConfig**: Session management settings

**Example:**

```dart
final config = EngineConfig(
  security: EngineSecurityFeatures(
    csrfProtection: true,
    maxRequestSize: 5 * 1024 * 1024,
    cors: CorsConfig(
      enabled: true,
      allowedOrigins: ['https://example.com'],
      allowCredentials: true,
    ),
  ),
  redirectTrailingSlash: true,
  handleMethodNotAllowed: true,
  multipart: MultipartConfig(
    maxFileSize: 10 * 1024 * 1024,
    allowedExtensions: {'jpg', 'png', 'pdf'},
  ),
);
```

### Engine Options (`engine_opt.dart`)

Functional configuration options for common settings:

- `withTrustedProxies()` - Configure proxy IP addresses
- `withMaxRequestSize()` - Set request body size limit
- `withRedirectTrailingSlash()` - Enable/disable slash redirects
- `withLogging()` - Configure request logging
- `withCors()` - Configure CORS settings
- `withStaticAssets()` - Setup static file serving
- `withMiddleware()` - Register global middleware
- `withMultipart()` - Configure file uploads
- `withCacheManager()` - Set custom cache manager
- `withSessionConfig()` - Configure sessions

**Example:**

```dart
final engine = Engine(
  options: [
    withTrustedProxies(['10.0.0.0/8', '172.16.0.0/12']),
    withMaxRequestSize(10 * 1024 * 1024),
    withCors(
      enabled: true,
      allowedOrigins: ['https://app.example.com'],
      allowedMethods: ['GET', 'POST', 'PUT', 'DELETE'],
    ),
    withLogging(
      enabled: true,
      level: 'info',
      requestHeaders: ['User-Agent', 'Referer'],
    ),
  ],
);
```

### Middleware Registry (`middleware_registry.dart`)

Manages middleware registration and resolution:

- **Factory-based Registration**: Register middleware by string identifier
- **Lazy Instantiation**: Create middleware instances on demand
- **Dependency Injection**: Provide container access during instantiation
- **Reference Resolution**: Replace middleware references with instances

**Example:**

```dart
final registry = MiddlewareRegistry();

registry.register('auth', (container) {
  return AuthMiddleware(container.get<UserService>());
});

registry.register('logging', (container) {
  return LoggingMiddleware(container.get<Logger>());
});

// Later, resolve middleware references
final middlewares = registry.resolveAll(
  [MiddlewareReference('auth'), MiddlewareReference('logging')],
  container,
);
```

### Route Patterns (`patterns.dart`)

Defines parameter type patterns for route matching:

**Built-in Types:**

- `int` - Integer numbers (`\d+`)
- `double` - Decimal numbers (`\d+(\.\d+)?`)
- `uuid` - UUID format
- `slug` - URL-friendly slugs (`[a-z0-9]+(?:-[a-z0-9]+)*`)
- `word` - Word characters (`\w+`)
- `string` - Any non-slash characters
- `date` - ISO date format (`\d{4}-\d{2}-\d{2}`)
- `email` - Email address format
- `url` - HTTP/HTTPS URL format
- `ip` - IPv4 address format

**Custom Types:**

```dart
// Register custom type pattern
registerCustomType('phone', r'\+?[1-9]\d{1,14}', (value) {
  return PhoneNumber.parse(value);
});

// Register global parameter pattern
registerParamPattern('id', r'\d+');

// Use in routes
engine.get('/users/:id', handler); // 'id' matches digits
engine.get('/contact/:phone:phone', handler); // 'phone' uses custom type
```

### Error Handling (`error_handling.dart`)

Configurable error handling with hooks:

- **Before Hooks**: Execute before error handling
- **Error Handlers**: Type-specific error handlers
- **After Hooks**: Execute after error handling

**Example:**

```dart
final errorHandling = ErrorHandlingRegistry();

// Add before hook for logging
errorHandling.addBefore((ctx, error, stack) {
  print('Error occurred: $error');
});

// Add typed error handler
errorHandling.addHandler<ValidationException>((ctx, error, stack) {
  ctx.response.statusCode = 400;
  ctx.response.json({'error': error.message});
  return true; // Handled
});

// Add after hook for cleanup
errorHandling.addAfter((ctx, error, stack) {
  // Cleanup resources
});

final engine = Engine(errorHandling: errorHandling);
```

### Parameter Utilities (`param_utils.dart`)

Extension methods for safe parameter extraction:

```dart
// In route handler
final id = req.params.require<int>('id'); // Throws if missing or wrong type
final slug = req.params.require<String>('slug');
final page = req.params['page'] as int?; // Optional parameter
```

## Request Flow

1. **HTTP Request arrives** → Engine receives raw `HttpRequest`
2. **Size Limiting** → Request wrapped with `WrappedRequest` for size checks
3. **Route Matching** → Engine finds matching `EngineRoute`
4. **Parameter Extraction** → Route parameters extracted and typed
5. **Global Middleware** → Execute engine-level middleware
6. **Route Middleware** → Execute route-specific middleware
7. **Handler Execution** → Execute route handler
8. **Error Handling** → Catch and process errors if they occur
9. **Response** → Send response to client
10. **Cleanup** → Remove request from active tracking

## Service Providers

Service providers extend the engine with additional functionality:

**Built-in Providers:**

- **CoreServiceProvider**: Registers core services (config, container, events)
- **RoutingServiceProvider**: Registers routing services (middleware registry)
- **LoggingServiceProvider**: Sets up logging infrastructure

**Custom Providers:**

```dart
class DatabaseServiceProvider extends ServiceProvider {
  @override
  void register() {
    container.singleton<Database>((c) {
      return Database(c.get<Config>().get('database.url'));
    });
  }

  @override
  void boot() {
    final db = container.get<Database>();
    db.connect();
  }
}
```

## HTTP/2 Support (`http2_server.dart`)

Optional HTTP/2 protocol support with:

- Stream multiplexing
- Server push capabilities
- Binary framing
- Header compression

**Configuration:**

```dart
final config = EngineConfig(
  http2: Http2Config(
    enabled: true,
    maxConcurrentStreams: 100,
    idleTimeout: Duration(minutes: 5),
    allowCleartext: false, // Require TLS
  ),
);
```

## Best Practices

### 1. Use Configuration Options

Prefer `EngineOpt` functions for common settings:

```dart
Engine(options: [
  withCors(enabled: true),
  withTrustedProxies(['10.0.0.0/8']),
]);
```

### 2. Register Middleware by Name

Use middleware registry for reusable middleware:

```dart
registry.register('api', (c) => ApiMiddleware());

engine.group(
  path: '/api',
  middlewares: [MiddlewareReference('api')],
);
```

### 3. Use Typed Parameters

Leverage type casting for route parameters:

```dart
engine.get('/users/:id:int', (req) {
  final id = req.params.require<int>('id'); // Already an int!
});
```

### 4. Organize Routes with Groups

Group related routes together:

```dart
engine.group(
  path: '/admin',
  middlewares: [AuthMiddleware(), AdminMiddleware()],
  builder: (router) {
    router.get('/users', listUsers);
    router.get('/settings', showSettings);
  },
);
```

### 5. Named Routes for URL Generation

Name important routes for easy URL generation:

```dart
engine.get('/users/:id/edit', editUser).name('users.edit');

// Later
final url = engine.route('users.edit', {'id': 123});
```

## Performance Considerations

1. **Route Compilation**: Routes are compiled once at startup into efficient regex patterns
2. **Middleware Resolution**: Middleware references are resolved once during route building
3. **Request Tracking**: Active requests are tracked for graceful shutdown
4. **HTTP/2 Multiplexing**: Multiple requests can be handled concurrently on a single connection
5. **Static File Caching**: Static files can be cached to reduce disk I/O

## Testing

The engine provides test-friendly APIs:

```dart
@visibleForTesting
ShutdownController? get shutdownController;

@visibleForTesting
Map<String, WebSocketEngineRoute> get debugWebSocketRoutes;
```

## See Also

- [Router Documentation](../router/README.md) - Route definition and organization
- [Middleware Documentation](../middleware/README.md) - Writing custom middleware
- [Provider Documentation](../provider/README.md) - Creating service providers
- [Configuration Documentation](../config/README.md) - Application configuration