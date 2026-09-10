# routed_cli

CLI runtime and command framework helpers for Routed.

This package provides reusable command-runner and dev-server utilities used by
Routed's CLI surface, including:

- `CliLogger`
- `CliVersion`
- `RoutedCommandRunner`
- `BuildCommand`
- `ProjectCommandsLoader`
- `DevServerRunner`

It is intended for internal ecosystem composition and advanced custom command
integrations.

`routed_cli` is a command-line package, not an `Engine` provider. Install it as
a development dependency and run commands with
`dart run routed_cli:routed ...`; keep runtime provider initialization in
`routed` or the relevant adapter package. The executable discovers
`lib/commands.dart` and exposes its `buildProjectCommands()` commands alongside
the built-in CLI commands. It also bootstraps `lib/app.dart` for project
command discovery, so commands registered by the application's service
providers through `CliCommandRegistry` are available from the same CLI.
Provider discovery uses the conventional top-level `createEngine()` entrypoint
in `lib/app.dart`; Worker-only entrypoints such as
`createCloudflareEngine(environment)` remain host-specific.

Deployment adapters own their target-specific options. Applications using
`routed_node` can add `...routedNodeCliProviders()` to the providers returned by
`createEngine()`; that contributes `routed deploy` with Cloudflare, Netlify, and
Vercel options without coupling `routed_cli` to a runtime host.

Build a native server binary with the same engine and provider command
registrations used by the application:

```bash
routed cli build
# equivalent shorthand:
routed build
./build/server                 # starts the HTTP server
./build/server schedule:work   # runs a provider-owned command
```

The build writes a generated entrypoint under `.dart_tool/routed`, compiles it
with `dart compile exe`, and includes commands registered by providers and by
`lib/commands.dart`. Use `--output`, `--entry`, or repeatable `--define` to
customize the build.

For a JavaScript Node.js host, use the Node target. It generates a listener
entrypoint backed by `package:routed_node/node.dart`, compiles with dart2js,
and keeps the same provider and project command registration. The generated
entrypoint reads command arguments from Node's `process.argv`, since dart2js
does not populate `main(args)` for a standalone Node bundle:

```bash
routed build --target node
node build/server.js
node build/server.js schedule:work
```

Runtime packages should contribute commands from their
`ServiceProvider.registerCliCommands` hook. This keeps the command's
implementation with the feature package while leaving `routed_cli` as the
host adapter. For example, installing `RoutedSchedulerProvider` makes
`routed schedule` available without importing `routed_cli` from
`routed_jobs`.

New projects created by `routed create` use a typed `lib/config.dart` bootstrap.
Add provider-owned configuration there and let `lib/app.dart` continue to own
routes. The CLI loads `createEngine()`, so route inspection, OpenAPI generation,
and deployment use the same typed provider setup as the running application.

Template selection controls optional provider composition. `basic` and `api`
include `RoutedDatabaseProvider` with a file-backed SQLite manager and Ormed
migration support. `fullstack` adds `ViewServiceProvider`, while `web` adds
typed view, storage, and static-mount providers. The generated config imports
each provider's public package and constructs it explicitly:

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_database/routed_database.dart';
import 'package:routed_storage/routed_storage.dart';
import 'database.dart';

AppConfig config() => AppConfig(
  providers: [
    CoreServiceProvider(),
    RoutingServiceProvider(),
    RoutedDatabaseProvider(
      manager: createDatabaseManager(),
      migrations: appMigrations,
      migrateOnBoot: true,
    ),
    RoutedStorageProvider(
      configuration: StorageConfig(root: 'storage/app'),
    ),
  ],
);
```

The generated `lib/database.dart` uses SQLite for local development and keeps
the migration list codegen-free. Handlers can query it through `ctx.db()`.
For Cloudflare D1, replace the SQLite factory with `openCloudflareD1` in an
environment-aware engine while keeping the same Routed database provider.

For a Worker that is ready for D1 and Routed authentication, start with the
Cloudflare template:

```bash
routed create --name edge_app --template cloudflare
cd edge_app
wrangler d1 create edge_app-db
wrangler secret put SESSION_KEY
routed deploy --target cloudflare \
  --cloudflare-factory environment \
  --d1 DB=edge_app-db:DATABASE_ID \
  --var AUTH_ORIGIN=https://edge-app.example.com
```

The generated Worker uses `routed_auth` with `routed_auth_cloudflare` and
stores credentials in the same D1 binding under a namespaced schema. Set
`AUTH_ORIGIN` to the exact HTTPS browser origin and keep `SESSION_KEY` in a
secret binding. The generated `AllowAllAuthRateLimiter` is an explicit starter
placeholder; replace it with a durable application limiter before production.

For the local templates, add authentication and its server/client plugins only
when the application uses them. Configuration is ordinary typed Dart code:
generated projects do not use YAML files, string-key lookups, or a global driver
registry.

The username-first server plugin can be selected at creation time; no other
auth plugin is added with it:

```bash
dart run routed_cli:routed create --name my_app \
  --auth-plugin username
```

For a Cloudflare Durable Object, pass each binding as `BINDING=ClassName`.
Routed generates the Dart factory registration, Wrangler binding, SQLite
migration, and named Worker class export:

```bash
routed deploy --target cloudflare \
  --durable-object COUNTER=Counter \
  --durable-object ROOMS=ChatRoom
```

For D1, pass each binding as `BINDING=DATABASE_NAME:DATABASE_ID`:

```bash
routed deploy --target cloudflare \
  --d1 DB=app-db:00000000-0000-0000-0000-000000000000
```

Applications that open host bindings themselves can select an environment
factory. If `lib/app.dart` exports
`createCloudflareEngine(CloudflareEnvironment)`, use:

```bash
routed deploy --target cloudflare \
  --entry package:my_app/app.dart \
  --cloudflare-factory environment \
  --var AUTH_ORIGIN=https://example.workers.dev \
  --d1 DB=app-db:00000000-0000-0000-0000-000000000000
```

This generates `defineCloudflareFetchFactoryWithEnvironmentAsync` so D1 and
other typed Worker bindings are supplied by the host at request time.

### Frontend Fetch SSR

Any frontend that produces a Fetch-compatible SSR module can embed its SSR
handler and complete static build into the same Cloudflare Worker. For example,
a React Dart project using `react_server_routed` can run:

```bash
dart run react_tool:react build --release
routed deploy --target cloudflare \
  --ssr-entry build/react/ssr.entry.mjs
```

The CLI copies the complete generated frontend build into the deployment
bundle, including the browser bundle, CSS, and other static assets. The
containing build directory is inferred from the `--ssr-entry` path, and the
entry module's filename is preserved. The generated SSR module must export the
standard Fetch handler used by `/__ssr`. A frontend-specific client can target
`/__ssr` as needed. The generated Wrangler configuration also enables
`global_fetch_strictly_public`, which Cloudflare requires when the application
fetches another Worker in the same zone. The option is opt-in; ordinary Routed
deployments are unchanged.

Use repeatable `--var NAME=VALUE` options for non-secret Worker variables.
Secrets such as session keys must still be provisioned through Wrangler or a
secret manager. `--var` writes all supplied values as plaintext to the
generated config, so do not pass secrets with this option.

R2 buckets, Queue producers, and Worker-to-Worker service bindings use the
same `BINDING=RESOURCE_NAME` form:

```bash
routed deploy --target cloudflare \
  --r2 FILES=app-files \
  --queue EVENTS=app-events \
  --service PROFILE_API=profile-api
```

Containers, Workflows, and Secrets Store bindings can also be emitted in the
generated Wrangler configuration:

```bash
routed deploy --target cloudflare \
  --container APP=AppContainer\|./Dockerfile\|8080\|3 \
  --workflow BILLING=billing-workflow:BillingWorkflow:billing-worker \
  --secrets-store PAYMENTS_KEY=store-id:PAYMENTS_API_KEY
```

Container values are `BINDING=CLASS_NAME|IMAGE|PORT|MAX_INSTANCES`; the port
defaults to `8080` and the maximum instance count is optional. Routed exports a
small Durable Object wrapper that starts the container and forwards Fetch
requests to that port. A Workflow `SCRIPT_NAME` is optional when the Workflow
class is in the same Worker; use it when the Workflow is hosted by another
Worker. Secrets Store values are never written to the generated config.

The application entry library must export each Dart Durable Object class, and
each constructor must accept `(CloudflareDurableObjectState,
CloudflareEnvironment)` through the `CloudflareDurableObject` base class.
Container classes are generated by the deploy command from the Container
descriptor and do not need to be Dart classes.
