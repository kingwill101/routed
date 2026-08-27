# routed_cli

CLI runtime and command framework helpers for Routed.

This package provides reusable command-runner and dev-server utilities used by
Routed's CLI surface, including:

- `CliLogger`
- `CliVersion`
- `RoutedCommandRunner`
- `ProjectCommandsLoader`
- `DevServerRunner`

It is intended for internal ecosystem composition and advanced custom command
integrations.

`routed_cli` is a command-line package, not an `Engine` provider. Install it as
a development dependency and run commands with
`dart run routed_cli:routed ...`; keep runtime provider initialization in
`routed` or the relevant adapter package. The executable discovers
`lib/commands.dart` and exposes its `buildProjectCommands()` commands alongside
the built-in CLI commands.

New projects created by `routed create` use a typed `lib/config.dart` bootstrap.
Add provider-owned configuration there and let `lib/app.dart` continue to own
routes. The CLI loads `createEngine()`, so route inspection, OpenAPI generation,
and deployment use the same typed provider setup as the running application.

Template selection controls optional provider composition. `basic` and `api`
start with only `CoreServiceProvider` and `RoutingServiceProvider`; `fullstack`
adds `ViewServiceProvider`; and `web` adds typed view, storage, and static-mount
providers. The generated config imports each provider's public package and
constructs it explicitly:

```dart
import 'package:routed_core/routed_core.dart';
import 'package:routed_storage/routed_storage.dart';

AppConfig config() => AppConfig(
  providers: [
    CoreServiceProvider(),
    RoutingServiceProvider(),
    RoutedStorageProvider(
      configuration: StorageConfig(root: 'storage/app'),
    ),
  ],
);
```

Add authentication and its server/client plugins only when the application
uses them. Configuration is ordinary typed Dart code: generated projects do
not use YAML files, string-key lookups, or a global driver registry.

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

### React Fetch SSR

React Dart projects using `react_server_routed` can embed the generated Fetch
SSR endpoint into the same Cloudflare Worker:

```bash
dart run react_tool:react build --release
routed deploy --target cloudflare \
  --build-dir build/react
```

The CLI copies the complete generated frontend build into the deployment
bundle, including the browser bundle, CSS, and other static assets. The build
directory must contain `ssr.entry.mjs`; the CLI reserves
`/__react/ssr` for rendering requests. Point the JavaScript `ReactSsrClient` in
the Routed application at that relative endpoint. The generated Wrangler
configuration also enables
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
