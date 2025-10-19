## 1. Context Helpers
- [x] 1.1 Add synchronous `requireFound` helper on `EngineContext` that returns the value or throws `NotFoundError` and records it.
- [x] 1.2 Add asynchronous `fetchOr404` helper accepting `FutureOr<T?>` producers.

## 2. Tests & Docs
- [x] 2.1 Cover the new helpers in unit tests (success and failure cases) to ensure errors propagate and context errors list is updated.
- [x] 2.2 Document usage in the advanced events/views guide so developers discover the new shortcut.
