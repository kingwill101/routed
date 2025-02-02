# Cookie Handling Example

Demonstrates how to work with cookies including setting, reading, and managing cookie attributes.

## Features

- Setting cookies with attributes
- Reading cookie values
- Setting multiple cookies
- Cookie deletion
- Cookie preferences example

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
// Setting a cookie
ctx.setCookie(
  'user',
  'john_doe',
  maxAge: 3600,
  path: '/',
  secure: true,
  sameSite: SameSite.none,
);

// Reading a cookie
final theme = ctx.cookie('theme') ?? 'light';

// Deleting a cookie
ctx.setCookie('user', '', maxAge: 0);
``` 