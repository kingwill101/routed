# {{{routed:humanName}}}

A Routed starter that serves HTML and JSON in the same application.

## Commands

```bash
dart pub get
```

```
dart run routed dev
```

- Visit http://localhost:8080 for the web UI.
- Call http://localhost:8080/api/todos for JSON responses.

The app renders vanilla HTML and exposes a simple REST API. Swap the front end
for HTMX, a SPA framework, or your favourite renderer while keeping the API layer
in Dart.
