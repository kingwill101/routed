# Config Demo

This example application demonstrates Routed's configuration pipeline and CLI commands.

## Prerequisites

- Dart SDK ^3.9
- Run `dart pub get` inside this directory to fetch dependencies.

## Available configuration

Configuration is resolved from the following sources (highest priority last):

1. Defaults advertised by service providers (`MailProvider`)
2. Provider manifest in `config/http.yaml` (enables `config_demo.mail`)
3. `.env`, `.env.local`
4. `config/*.yaml`
5. Runtime overrides provided by the engine

Before parsing, files under `config/` are rendered with Liquify. The loader builds a template context from `.env` /
`.env.local`, `Platform.environment`, and string overrides you pass at runtime. Keys that contain double underscores are
normalised into dotted paths, so `SESSION__CONFIG__APP_KEY` becomes available as `{{ session.config.app_key }}` inside
templates. Every value is also published under the `env.*` namespace, so you can reference `{{ env.APP_KEY }}` alongside
the legacy `{{ APP_KEY }}` form.

For lists use bracket notation (`{{ static.mounts[0].route }}`) — Liquid treats digits after a dot as property lookup,
so brackets make sure array indexes resolve correctly.

### Liquid templating quick start

```dotenv title=".env"
APP__NAME=Liquid Config Demo
MAIL__HOST=smtp.dev.internal
SESSION__CONFIG__APP_KEY=base64:demo-app-key-please-update
LOGGING__EXTRA_FIELDS__DEPLOYMENT=liquid-demo
```

```yaml title="config/mail.yaml"
driver: smtp
host: "{{ mail.host | default: 'localhost' }}"
port: {{ mail.port | default: 2525 }}
from: "{{ mail.from | default: 'demo@example.dev' }}"
credentials:
  username: "{{ mail.credentials.username | default: 'demo' }}"
  password: "{{ mail.credentials.password | default: 'secret' }}"
```

Editing `.env` or any file under `config/` while the server runs updates the merged configuration returned by `/`. The
engine is created with `watch: true`, so the filesystem watcher triggers `ConfigReloadedEvent` and rebuilds the
container automatically.

The `/` route dumps the resolved configuration so you can see how defaults, template-driven files, environment
variables, and runtime overrides combine. Notice that `.env` sets `FEATURES__BETA_BANNER=false`, but the demo passes
`configItems: {'features.beta_banner': true}` to showcase runtime precedence.

The `MailProvider` implements `ProvidesDefaultConfig`, registering defaults that appear in the `ConfigRegistry`. When
the loader merges the application config, any missing keys are populated with these defaults before the Liquid templates
run.

### Custom drivers

The demo also registers bespoke storage and cache drivers (`memory_ephemeral` and `in_memory`) to exercise the driver
registries. Check the code under `lib/drivers/` and the `/` payload to see how their documentation entries surface
alongside the built-ins. Run `dart run routed_cli provider:list --config` to inspect the merged defaults and confirm the
documented paths.

## Running the server

```sh
dart run bin/server.dart
```

Visit `http://127.0.0.1:8080/` to inspect the merged configuration. The
`/override` route demonstrates `Config.runWith`, temporarily overriding
`app.name` for the scope of a request.

To verify graceful shutdown, start the server and press `Ctrl+C` (SIGINT). You
should see "Shutting down..." logs while the process drains in-flight requests
before exiting.

### Smoke test compression

With the server running, request a route using `curl --compressed` to confirm
the built-in middleware negotiates an encoding:

```bash
curl --compressed -I http://127.0.0.1:8080/health
```

Expect to see `content-encoding: br` (or `gzip`) and a `Vary: Accept-Encoding`
header in the response.

## Using the CLI

The example depends on `routed_cli`, exposing configuration commands:

```sh
# Scaffold config/ and .env (already checked in here)
dart run routed_cli config:init

# Copy stubs from dependencies (no-op for this example)
dart run routed_cli config:publish routed

# Generate a cached Dart + JSON configuration snapshot
dart run routed_cli config:cache

# Remove generated cache artifacts
dart run routed_cli config:clear

# Inspect the provider manifest declared in config/http.yaml
dart run routed_cli provider:list

# Toggle the demo mail provider (enabled by default)
dart run routed_cli provider:disable config_demo.mail
dart run routed_cli provider:enable config_demo.mail

# Generate driver starters (storage or cache)
dart run routed_cli provider:driver storage demo_driver
dart run routed_cli provider:driver --type cache demo_store
```

The cache command writes the merged configuration to
`lib/generated/routed_config.dart` so production builds can start without IO.

## Changing environments

Set `APP__ENV=testing` inside `.env` to load `config/testing/*.yaml`.
Touch `.env` (or restart the server) and the watcher will reload the config so the `/` payload reflects the testing mail
overrides.
