## 0.2.1

- Documented the package with badges, funding link, and a runnable Shelf sample.

## 0.2.0

- Fixed the Shelf response translator to stream bytes into the underlying
  `HttpResponse` without double-closing the sink, eliminating sporadic `StateError`
  failures under concurrent load.
- Added property-based adapter tests (tagged `property`) and shared `dart_test.yaml`
  defaults to keep the Shelf bridge aligned with the latest `server_testing`
  transports.

## 0.1.0

### Features

#### Shelf Integration

- **ShelfRequestHandler** implementation for seamless integration of Shelf applications with server_testing
- **Automatic request/response translation** between `dart:io` HttpRequest/HttpResponse and Shelf Request/Response
- **Support for both testing modes**: in-memory and real HTTP server (ephemeral server)
- **Shelf Pipeline support** with middleware integration
- **Full compatibility** with Shelf Router and other Shelf ecosystem packages

#### Testing Utilities

- **Fluent test API** from server_testing available for Shelf applications
- **JSON API testing** with assertable JSON utilities
- **Header and status assertions** for response validation
- **Body content assertions** including partial matching

#### Examples

- Basic hello world example demonstrating request handling
- JSON API testing with nested assertions
- Pipeline integration with middleware
- Real HTTP server testing mode examples

### Tests

- Integration tests with Shelf Router
- Request/response translation unit tests
- Full request handler test suite covering all HTTP methods
- Pipeline and middleware integration tests

### Deprecations

None - Initial release
