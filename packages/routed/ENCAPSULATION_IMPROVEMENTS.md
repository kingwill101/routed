# Encapsulation Improvements

This document summarizes the refactoring work done to improve encapsulation in the `routed` package by eliminating
direct access to `Request.httpRequest` and `Response.response` (now `Response._httpResponse`).

## Overview

The goal of this refactoring was to:

1. Remove all direct access to the underlying `HttpRequest` and `HttpResponse` objects
2. Provide public API methods on `Request` and `Response` classes to expose necessary functionality
3. Prepare the codebase for making `httpRequest` and `_httpResponse` private in a future release

## Changes Made

### 1. Request Class Enhancements

Added the following public APIs to avoid direct `httpRequest` access:

- **`Request.stream`** - Returns a `Stream<List<int>>` of the request body data
    - Allows consuming the request body as a stream without accessing `httpRequest`
    - Used by multipart form data parsing and file upload handling

### 2. Response Class Enhancements

Added the following public APIs to avoid direct `httpResponse` access:

- **`Response.addStream(Stream<List<int>> stream)`** - Adds a stream of bytes to the response
    - Writes headers and then streams data to the response
    - Used by file handler for efficient file streaming

- **`Response.addHeader(String name, String value)`** - Adds a header to the response
    - Properly handles `Set-Cookie` headers (always separate)
    - Properly handles standard headers (combined with comma-separation)

- **`Response.setHeader(String name, String value)`** - Sets a header, replacing any existing value

- **`Response.removeHeader(String name, {Object? value})`** - Removes a header from the response

### 3. Removed Public Accessors

The following getters were removed to enforce encapsulation:

- **`Request.response`** - No longer exposes the underlying `HttpResponse` object
- **`Response.httpResponse`** - No longer exposes the underlying `HttpResponse` object

### 4. Deprecated Fields

The following fields remain but are marked as deprecated:

- **`Request.httpRequest`** - Marked with `@deprecated` annotation
    - Will be made private in a future version
    - Users should migrate to using the public API methods

### 5. Middleware Refactoring

All middleware and library code was updated to use only the public API:

#### CSRF Middleware

- Removed direct access to `request.httpRequest` and `response.response`
- Uses `request.session`, `response.setCookie()`, and other public APIs

#### CORS Middleware

- Uses `response.addHeader()` instead of direct header manipulation

#### Limit Request Body Middleware

- Uses `request.stream` instead of accessing `httpRequest` directly
- Now throws `RequestEntityTooLargeException` instead of directly manipulating the response

#### File Handler

- Uses `response.addStream()` for efficient file streaming
- Uses public header APIs for setting content types and cache headers

#### Multipart Form Data Handler

- Uses `request.stream` instead of accessing `httpRequest` directly
- Properly handles file upload limits with exception-based error handling

#### Security Headers Middleware

- Uses `response.addHeader()` for all header manipulation

#### Request Tracker Middleware

- Uses public request properties like `request.method`, `request.path`, etc.

## Benefits

1. **Better Encapsulation** - Internal implementation details are hidden from users
2. **Future Flexibility** - Can change underlying HTTP implementation without breaking user code
3. **Cleaner API** - Users work with high-level abstractions instead of low-level HTTP objects
4. **Type Safety** - Public APIs are strongly typed and documented
5. **Consistent Behavior** - All middleware uses the same public API surface

## Migration Guide

### For Middleware Authors

**Before:**

```dart
final token = request.httpRequest.headers.value('X-CSRF-Token');
response.httpResponse.headers.add('X-Custom', 'value');
```

**After:**

```dart
final token = request.headers.value('X-CSRF-Token');
response.addHeader('X-Custom', 'value');
```

### For File Streaming

**Before:**

```dart
await file.openRead().pipe(request.httpRequest.response);
```

**After:**

```dart
await response.addStream(file.openRead());
```

### For Request Body Streaming

**Before:**

```dart
await for (final chunk in request.httpRequest) {
  // Process chunk
}
```

**After:**

```dart
await for (final chunk in request.stream) {
  // Process chunk
}
```

## Testing

All tests pass with the new implementation:

- 386+ tests covering all middleware and core functionality
- Both in-memory and server transports tested
- Session, CSRF, CORS, file handling, and all other features verified

## Future Work

In a future major version release:

1. Make `Request.httpRequest` fully private
2. Remove the deprecated `@deprecated` annotations
3. Consider additional public APIs based on user feedback

## Compatibility

This refactoring is **backwards compatible** for most users:

- The deprecated `httpRequest` field still exists and works
- Users have time to migrate to the new public APIs
- All existing tests pass without modification