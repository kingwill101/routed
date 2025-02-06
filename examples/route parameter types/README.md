# Routed Parameter Types Example

This example demonstrates the various parameter types available in the routed package.

## Features Demonstrated

### Built-in Parameter Types
- `int`: Integer values
- `double`: Floating point numbers
- `uuid`: UUID strings
- `slug`: URL-friendly slugs
- `email`: Email addresses
- `url`: URLs
- `ip`: IP addresses
- `string`: Any non-slash characters
- `word`: Word characters only

### Additional Features
- Custom type patterns
- Global parameter patterns
- Multiple parameters in routes
- Type validation
- Parameter extraction

## Running the Example

1. Start the server:
```bash
dart run bin/server.dart
```

2. Run the client:
```bash
dart run bin/client.dart
```

## Parameter Type Examples

### Integer Parameter
```dart
// Matches: /items/123
engine.get('/items/{id:int}', (ctx) {
  final id = ctx.param('id'); // Returns 123 as int
});
```

### Double Parameter
```dart
// Matches: /prices/99.99
engine.get('/prices/{amount:double}', (ctx) {
  final amount = ctx.param('amount'); // Returns 99.99 as double
});
```

### UUID Parameter
```dart
// Matches: /users/123e4567-e89b-12d3-a456-426614174000
engine.get('/users/{id:uuid}', (ctx) {
  final uuid = ctx.param('id');
});
```

### Custom Type Pattern
```dart
// Register custom type
registerCustomType('phone', r'\d{3}-\d{3}-\d{4}');

// Use in route: /contact/123-456-7890
engine.get('/contact/{phone:phone}', (ctx) {
  final phone = ctx.param('phone');
});
```

## Code Structure

- `bin/server.dart`: Server implementation with parameter type examples
- `bin/client.dart`: Test client demonstrating parameter types
- `pubspec.yaml`: Project dependencies

## Response Examples

### Integer Parameter
```json
{
  "type": "integer",
  "value": 123,
  "dart_type": "int"
}
```

### Email Parameter
```json
{
  "type": "email",
  "value": "user@example.com",
  "valid": true
}
```

### Multiple Parameters
```json
{
  "order_id": 123,
  "sku": "SKU123",
  "price": 49.99
}
```