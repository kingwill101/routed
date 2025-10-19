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