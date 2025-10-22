# Project Commands Demo

This example showcases how a Routed application can expose custom CLI commands by
defining `lib/commands.dart`. When `dart run routed_cli <command>` is executed
inside the project directory, Routed CLI will automatically load the exported
commands and make them available alongside the built-ins.

## Setup

```bash
dart pub get
```

To run the HTTP server locally:

```bash
dart run bin/server.dart
# or with hot reload + tooling
dart run routed_cli dev

# See built-in and project-specific commands
dart run routed_cli --help
```

## Custom Commands

Two project commands are provided:

- `demo:greet` – prints a friendly greeting and demonstrates reading options
  from `argParser`.
- `routes:dump` – boots the application, builds the route manifest, and writes
  it to a JSON file for tooling or documentation.

Examples:

```bash
# Print a greeting
dart run routed_cli demo:greet --name "Routed fan"

# Dump routes to build/routes.json (pretty printed by default)
dart run routed_cli routes:dump --output build/routes.json

# Skip pretty printing
dart run routed_cli routes:dump --no-pretty
```

The command entrypoint can register additional tasks (queue workers, seeders,
diagnostics) without modifying the global CLI.
