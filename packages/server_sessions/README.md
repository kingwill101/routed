# server_sessions

Framework-agnostic session runtime. It uses the shared contracts and cache
abstractions supplied by the server ecosystem.

## Using with Routed

This package supplies session stores but does not initialize a Routed provider.
Use `routed_sessions` for `EngineContext` session helpers: initialize
`RoutedSessionsProvider` alongside `Engine.defaultProviders` and add
`sessionMiddleware` to the engine. The batteries-included `routed` facade
registers the provider catalogue automatically.
