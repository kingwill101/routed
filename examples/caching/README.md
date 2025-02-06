# Routed Caching Example

This example demonstrates various caching capabilities in the routed package.

## Features Demonstrated

- Basic cache operations (get/set)
- Cache expiration
- Increment/decrement operations
- Remember cache functionality
- Multiple cache stores (array and file)

## Running the Example

1. Start the server:
```bash
dart run bin/server.dart
```

2. In another terminal, run the client:
```bash
dart run bin/client.dart
```

## API Endpoints

### GET /cached-value
Demonstrates basic cache operations:
- First request: Stores value in cache
- Subsequent requests: Returns cached value

### GET /counter
Demonstrates increment/decrement operations:
- Initializes counter to 0
- Increments by 5
- Decrements by 2
- Returns final value

### GET /remember
Demonstrates remember cache functionality:
- Computes value only if not in cache
- Returns cached value on subsequent requests

## Cache Stores

The example configures two cache stores:

1. Array Store:
   - In-memory storage
   - No serialization
   - Fastest but temporary

2. File Store:
   - Persistent storage
   - Data stored in 'cache' directory
   - Survives application restarts

## Code Structure

- `bin/server.dart`: Server implementation with cache examples
- `bin/client.dart`: Test client to demonstrate cache behavior
- `pubspec.yaml`: Project dependencies
