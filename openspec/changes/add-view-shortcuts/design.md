## Overview
Django's `get_object_or_404()` and friends collapse a common null-check + 404 pattern into a helper. Routed handlers frequently do:

```dart
final user = await repo.findById(id);
if (user == null) {
  throw NotFoundError(message: 'User not found');
}
```

We can embed this behaviour in `EngineContext` with methods that:

1. Accept either a resolved value or a callback returning `FutureOr<T?>`.
2. When the result is `null`, build a `NotFoundError`, record it via `addError`, and throw it so upstream middleware (or tests) can respond.
3. Otherwise return the value for the happy path.

This keeps the API surface small while remaining flexible: the synchronous variant covers already-resolved values, and the async variant makes it easy to pass repository futures.

## Error recording
`EngineContext` already exposes `addError` which stores `EngineError`s for later inspection/logging. We'll use that to mirror Django's diagnostics and ensure our 404 helper participates in existing tooling.

## Surface area
The helpers live in `context/render.dart` (or a dedicated support part) alongside other high-level conveniences. They will be exported automatically through `package:routed/routed.dart`. No new imports are needed beyond the existing context exports.
