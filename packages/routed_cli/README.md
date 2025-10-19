# routed_cli

A fast, minimalistic backend framework CLI for Dart.

This CLI is intended to complement the `routed` package with developer tooling similar to other modern server
frameworks. It focuses on a smooth local development experience with hot reload capability planned via `hotreloader`.

- Minimum Dart SDK: 3.9.2
- Planned hot reload engine: hotreloader ^4.3.0 (requires Dart >= 3.0.0)

## Install

You can run the CLI directly without installing it globally:

- From a project that depends on `routed_cli`:
    - `dart run routed_cli --help`
    - or `dart run routed --help` (via the `executables` mapping)

To install globally (useful for running from anywhere):

- From a published package (future):
    - `dart pub global activate routed_cli`
- From source (local path):
    - `dart pub global activate --source path /path/to/packages/routed_cli`

Once activated globally, invoke the `routed` executable:

- `routed --help`

## Usage

```
A fast, minimalistic backend framework for Dart.

Usage: routed <command> [arguments]

Global options:
-h, --help       Print this usage information.
    --version    Print the current version.

Available commands:
  build    Create a production build. (stub)
  create   Scaffold a new Routed app with healthy defaults.
  dev      Run a local development server. (hot reload ready - see below)
  list     Lists all the routes on a Routed project. (stub)
  new      Create a new route or middleware for Routed. (stub)
  update   Update the Routed CLI. (stub)
```

## Quickstart

1. Scaffold a new project (optional but recommended):

```
dart run routed_cli create --name hello_world
cd hello_world
dart pub get
```

The scaffold provides `bin/server.dart`, config files, and a starter README. Any existing project with a
`bin/server.dart` entrypoint works too.

2. Start the dev server:

From a local dependency:

- `dart run routed dev --entry bin/server.dart -p 8080 -H 127.0.0.1`

From a global install:

- `routed dev --entry bin/server.dart -p 8080 -H 127.0.0.1`

Options:

- `--entry, -e` Path to the entrypoint that starts your app (default: `bin/server.dart`).
- `--port, -p` Port to bind (default: `8080`).
- `--host, -H` Host to bind (default: `127.0.0.1`).
- `--watch` Repeatable; additional paths to watch (reserved for upcoming hot reload orchestration).
- `--verbose, -v` More output.
- `--bootstrap=false` Skip generating the hot reload bootstrap (useful for quick smoke tests).

Notes:

- The CLI currently passes `--host` and `--port` to your entrypoint. If your server doesn’t parse these flags, they will
  be ignored. See “Accepting host/port from the CLI” below.

## Hot Reload

Hot reload is a top priority feature for the `dev` command. The plan is to enable it using the
excellent [hotreloader](https://pub.dev/packages/hotreloader) package.

Phase 1 (in place now):

- The `dev` command launches the target Dart program with `--enable-vm-service`. This is required for hot reload support
  in the Dart VM.
- You can already integrate `hotreloader` directly into your app entrypoint to get hot reload behavior today (see
  below).

Phase 2 (planned):

- The CLI will optionally orchestrate watching (via `--watch`) and perform targeted reloads via the VM service or by
  signaling the `hotreloader` instance.
- Additional ergonomics: debouncing, filtering, and clear logging around reload successes/failures.

### Enable hotreloader in your app entrypoint

1) Add as a dev dependency:

```
dart pub add --dev hotreloader
```

2) Initialize the reloader in your entrypoint (e.g., `bin/server.dart`), making sure your process runs with
   `--enable-vm-service` (the CLI already does this):

```/dev/null/bin/server.dart#L1-200
import 'package:hotreloader/hotreloader.dart';
import 'package:routed/routed.dart';

Future<void> main(List<String> args) async {
  // Enable hot reload for this process.
  final reloader = await HotReloader.create(
    debounceInterval: const Duration(seconds: 1),
    onAfterReload: (ctx) {
      print('Hot reload: ${ctx.result}');
    },
  );

  final engine = Engine();

  // Example routes
  engine.get('/hello', (ctx) => ctx.string('Hello, World!'));

  await engine.serve(host: '127.0.0.1', port: 8080);

  // Cleanup on shutdown
  reloader.stop();
}
```

3) Start your app with the CLI:

```
routed dev --entry bin/server.dart -p 8080 -H 127.0.0.1
```

You can now edit files under `lib/` and see changes applied live.

## Accepting host/port from the CLI (optional)

The `dev` command passes `--host` and `--port` to your entrypoint. If you want to honor those values, parse them in your
server’s `main`:

```/dev/null/bin/server.dart#L1-200
import 'package:args/args.dart';
import 'package:routed/routed.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('host', defaultsTo: '127.0.0.1')
    ..addOption('port', defaultsTo: '8080');

  final result = parser.parse(args);
  final host = result['host'] as String;
  final port = int.parse(result['port'] as String);

  final engine = Engine();
  engine.get('/hello', (ctx) => ctx.string('Hello, from $host:$port!'));

  await engine.serve(host: host, port: port);
}
```

If your app does not parse these flags, the values are simply ignored.

## Commands

- `dev`:
    - Starts your application in development mode with the Dart VM service enabled.
    - Prepares the ground for integrated hot reload.
    - Flags:
        - `--entry, -e`: Entrypoint file. Default: `bin/server.dart`
        - `--host, -H`: Host to bind. Default: `127.0.0.1`
        - `--port, -p`: Port to bind. Default: `8080`
        - `--watch`: Additional paths to watch for changes (planned integration)
        - `--verbose, -v`: Verbose logging

- `build` (stub): Create a production build.
- `create` (stub): Scaffold a new Routed app.
- `list` (stub): List all routes in a Routed project.
- `new` (stub): Create a new route or middleware.
- `update` (stub): Update the CLI.

## Roadmap

- Hot Reload Orchestration:
    - Integrate `hotreloader` with the CLI’s `--watch` to trigger reloads consistently.
    - Log reload summaries, failures, and timing.

- Developer Experience:
    - Colored, structured logs.
    - Friendly errors with suggested fixes (e.g., missing entry file, invalid flags).

- Generators:
- `create` and `new` to scaffold apps, routes, middleware, and configs (first pass lands with the basic app template).

- Introspection:
    - `list` to enumerate routes.
    - Diagnostics endpoints for development.

- Build:
    - `build` pipeline to produce deployable artifacts.

## Troubleshooting

- “Entry file not found”:
    - Ensure your `--entry` path exists relative to your current working directory.
    - Example: `routed dev --entry examples/basic_router/bin/server.dart`

- Hot reload doesn’t seem to apply:
    - Verify your app is running with `--enable-vm-service` (the `dev` command ensures this).
    - Ensure `hotreloader` is initialized in your entrypoint.
    - Make sure you’re editing files under directories watched by `hotreloader` (by default `lib/`).

- Port already in use:
    - Choose a different port via `-p` (e.g., `-p 3000`).

## Contributing

- Contributions are welcome. Focus areas include:
    - Hot reload orchestration and file watching.
    - Route listing, app scaffolding, and DX improvements.
    - Documentation and examples.

## License

Apache-2.0
