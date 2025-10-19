## ADDED Requirements

### Requirement: EngineContext view helpers
EngineContext SHALL provide helper APIs that enforce presence or throw `NotFoundError` so handlers avoid repeating null checks.

#### Scenario: requireFound returns value when present
- **GIVEN** a non-null model instance resolved in a handler
- **WHEN** `ctx.requireFound(model)` is invoked
- **THEN** the helper returns the model without mutating the context error list.

#### Scenario: requireFound throws NotFoundError when value missing
- **GIVEN** a null model result
- **WHEN** `ctx.requireFound(model)` is invoked with an optional message
- **THEN** a `NotFoundError` is thrown containing the message
- **AND** the context records the error via `ctx.errors`.

### Requirement: EngineContext SHALL support async fetch shortcut
EngineContext SHALL expose an asynchronous fetch shortcut that awaits a producer and throws `NotFoundError` when the result is absent.

#### Scenario: fetchOr404 awaits future and returns value
- **GIVEN** a repository method returning a future of an entity
- **WHEN** `await ctx.fetchOr404(() => repo.find(id))` resolves to a non-null entity
- **THEN** the entity is returned and no errors are registered on the context.

#### Scenario: fetchOr404 throws NotFoundError for null future result
- **GIVEN** a repository method returning a future that resolves to null
- **WHEN** `await ctx.fetchOr404(() => repo.find(id), message: 'User missing')`
- **THEN** a `NotFoundError` with message "User missing" is thrown
- **AND** the context error log captures the error.
