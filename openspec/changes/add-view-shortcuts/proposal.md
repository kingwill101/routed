## Summary
Add view helper shortcuts to routed's request context so handlers can "get or 404" resources and short-circuit with proper errors without repeating boilerplate. This mirrors Django's `get_object_or_404` convenience API and aligns with the parity roadmap.

## Motivation
- Handlers commonly fetch domain objects and then manually throw a 404. Centralising the pattern avoids typos and ensures logging / EngineError semantics stay consistent.
- Django developers expect helpers such as `get_object_or_404` and `require_GET`. Implementing the fetch-and-404 helper narrows the “Views & Shortcuts” delta in `DJANGO_COMPARISON.md`.
- Applications can remove repetitive null checks in controllers and keep business logic focused on success paths.

## Scope
- Extend `EngineContext` with synchronous and asynchronous shortcuts that take a value (or closure) and throw `NotFoundError` when no result exists, recording the error on the context.
- Provide optional message overrides so APIs can customise the 404 payload.
- Add targeted tests and documentation updates.
