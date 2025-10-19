## 0.1.0

### Features

#### Core Testing Utilities (Framework Independent)

- **AssertableJson** - Fluent API for making assertions on JSON objects
    - Type checking with `whereType<T>()`
    - Nested property access with dot notation
    - Array validation and iteration
    - Numeric comparisons (greater than, less than, between)
    - Pattern matching and contains operations
    - Schema validation with type checking
    - Property interaction tracking with `verifyInteracted()`
- **AssertableJsonString** - JSON string validation utilities
- **Numeric assertions** - Type-safe numeric comparison extensions
- **Conditional testing** - `when()` for conditional assertion chains

#### Routed Framework Integration

- **RoutedTransport** - Integration layer for testing Routed applications
- **Test client utilities** - HTTP request/response testing with Routed engine
- **Route testing helpers** - Simplified testing for route handlers
- **Multipart request support** - Builder API for testing file uploads
- **Integration test helpers** - Utilities for end-to-end testing

#### JSON Assertion Methods

- `has()` - Assert property existence
- `hasNested()` - Assert nested property with dot notation
- `where()` - Assert property value equality
- `whereType<T>()` - Assert property type
- `whereContains()` - Assert string/array contains value
- `whereIn()` - Assert value in list
- `count()` - Assert array length
- `each()` - Iterate and assert on array elements
- `isGreaterThan()`, `isLessThan()`, `isBetween()` - Numeric assertions
- `matchesSchema()` - Validate object structure against schema

### Tests

- Route testing examples with GET/POST/PUT/DELETE methods
- JSON assertion test suite
- Multipart request handling tests

### Deprecations

None - Initial release
