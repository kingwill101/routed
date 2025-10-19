# Middleware Tests

This directory contains comprehensive tests for all Routed middleware components. Each middleware has its own dedicated
test file with tests running in both `inMemory` and `ephemeralServer` transport modes.

## Test Structure

Each test file follows this pattern:

```dart
group('middlewareName', () {
  for (final mode in TransportMode.values) {
    group('with ${mode.name} transport', () {
      late TestClient client;

      tearDown(() async {
        await client.close();
      });

      test('specific behavior', () async {
        // Test implementation
      });
    });
  }
});
```

This ensures that every middleware is tested in both:

- **In-Memory Mode**: Fast, synchronous testing without network overhead
- **Ephemeral Server Mode**: Real HTTP server testing for integration scenarios

## Test Files

### `basic_auth_test.dart`

Tests HTTP Basic Authentication middleware:

- Credential validation
- WWW-Authenticate header handling
- Custom realm support
- Multiple user support
- Error handling for invalid/missing credentials

### `cors_test.dart`

Tests Cross-Origin Resource Sharing middleware:

- Wildcard origin handling
- Specific origin allowlists
- Preflight OPTIONS requests
- Credentials and origin reflection
- Custom headers and max-age
- Exposed headers configuration

### `csrf_test.dart`

Tests Cross-Site Request Forgery protection:

- Token generation and validation
- Cookie-based token storage
- Header-based token submission
- Token persistence across requests
- Safe method bypass (GET, HEAD, OPTIONS)
- Integration with session middleware

### `recovery_test.dart`

Tests error recovery middleware:

- Exception catching and handling
- Custom error handlers
- Default error responses
- Error type differentiation
- Stack trace availability
- Middleware chain preservation

### `request_tracker_test.dart`

Tests request timing and metadata tracking:

- Duration measurement
- Completion timestamp tracking
- Context data storage
- Multiple request independence
- Integration with logging
- Middleware chain compatibility

### `security_headers_test.dart`

Tests security header injection:

- Content Security Policy (CSP)
- X-Content-Type-Options
- Strict-Transport-Security (HSTS)
- X-Frame-Options
- Header combination
- Per-route configuration

### `timeout_test.dart`

Tests request timeout middleware:

- Timeout enforcement
- Fast request completion
- Different timeout durations
- Per-route timeout configuration
- Middleware chain interaction
- Various HTTP methods support

**Note**: Some timeout tests may fail in `ephemeralServer` mode due to timing variations in real network conditions.
This is expected behavior.

### `limit_request_body_test.dart`

Tests request body size limiting:

- Size limit enforcement
- Content-Length header validation
- Various payload sizes
- Different content types (JSON, multipart, binary)
- Per-route limit configuration
- Middleware chain short-circuiting

## Running Tests

### Run all middleware tests

```bash
dart test packages/routed/test/middleware/
```

### Run a specific middleware test

```bash
dart test packages/routed/test/middleware/basic_auth_test.dart
```

### Run only in-memory transport tests

```bash
dart test packages/routed/test/middleware/ --name "inMemory"
```

### Run only ephemeral server transport tests

```bash
dart test packages/routed/test/middleware/ --name "ephemeralServer"
```

### Run with verbose output

```bash
dart test packages/routed/test/middleware/ --reporter=expanded
```

## Test Coverage

Each middleware test file includes:

- ✅ Basic functionality tests
- ✅ Edge case handling
- ✅ Error scenarios
- ✅ Integration with other middleware
- ✅ Both transport mode validation
- ✅ Various HTTP methods support
- ✅ Configuration option testing

## Legacy Test File

`middleware_test.dart` - Original combined test file. This file has been superseded by the individual test files but is
kept for reference and backward compatibility.

## Contributing

When adding new middleware tests:

1. Create a new file named `{middleware_name}_test.dart`
2. Follow the dual-transport testing pattern
3. Include both positive and negative test cases
4. Test edge cases and error conditions
5. Document any transport-specific behaviors
6. Update this README with the new test file

## Known Issues

- **Timing Tests**: Timeout and request tracker tests may show slight variations in `ephemeralServer` mode due to
  network latency
- **Session-Based Tests**: CSRF tests require session middleware to be properly configured
- **Transport Differences**: Some behaviors may differ slightly between in-memory and server transports (this is
  expected and should be documented)

## Test Statistics

As of the last update:

- **Total Test Files**: 8
- **Total Tests**: ~130+ (including both transport modes)
- **Coverage**: All core middleware components
- **Transport Modes**: 2 (inMemory, ephemeralServer)