# Route Events Demo

This example prints the `BeforeRouting`, `RouteMatched`, `RouteNotFound`,
`RoutingError`, and `AfterRouting` events emitted by the engine.

## Run

```sh
cd examples/route_events
dart pub get
dart run bin/server.dart
```

Then hit the endpoints:

- `GET /` - see matching events in stdout.
- `GET /boom` - triggers `RoutingErrorEvent`.
- `GET /missing` - triggers `RouteNotFoundEvent`.
