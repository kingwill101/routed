# Routed package catalog

Package inventory for the Routed ecosystem. Versions below match the package
manifests in this checkout as of 2026-08-27.

## Framework and feature packages

| Package | Version | Role |
| --- | --- | --- |
| [`routed`](https://github.com/kingwill101/routed/tree/master/packages/routed) | `0.5.1` | Batteries-included framework facade and official provider catalogue |
| [`routed_core`](https://github.com/kingwill101/routed/tree/master/packages/routed_core) | `0.5.1` | Slim engine, routing, contexts, configuration, and lifecycle |
| [`routed_auth`](https://github.com/kingwill101/routed/tree/master/packages/routed_auth) | `0.2.1` | Routed auth plugin mounting, typed deployment binding, and runtime conformance support |
| [`routed_auth_cloudflare`](https://github.com/kingwill101/routed/tree/master/packages/routed_auth_cloudflare) | `0.1.1` | Durable Cloudflare D1 `AuthStore` adapter and typed migrations |
| [`routed_auth_sqlite`](https://github.com/kingwill101/routed/tree/master/packages/routed_auth_sqlite) | `0.1.1` | Durable Dart IO SQLite `AuthStore` adapter and typed migrations |
| [`routed_cache`](https://github.com/kingwill101/routed/tree/master/packages/routed_cache) | `0.2.1` | Cache services and context helpers for Routed |
| [`routed_logging`](https://github.com/kingwill101/routed/tree/master/packages/routed_logging) | `0.2.1` | HTTP logging provider and request logger helpers |
| [`routed_observability`](https://github.com/kingwill101/routed/tree/master/packages/routed_observability) | `0.1.1` | Health, metrics, tracing, and error observation |
| [`routed_rate_limit`](https://github.com/kingwill101/routed/tree/master/packages/routed_rate_limit) | `0.1.1` | Rate-limit service and middleware integration |
| [`routed_security`](https://github.com/kingwill101/routed/tree/master/packages/routed_security) | `0.1.1` | CORS middleware plus IP filtering, network matching, and trusted-proxy primitives |
| [`routed_sessions`](https://github.com/kingwill101/routed/tree/master/packages/routed_sessions) | `0.2.1` | Session stores, middleware, and context helpers |
| [`routed_storage`](https://github.com/kingwill101/routed/tree/master/packages/routed_storage) | `0.2.1` | Storage managers, disks, static-mount provider, middleware, and filesystem helpers |
| [`routed_views`](https://github.com/kingwill101/routed/tree/master/packages/routed_views) | `0.2.1` | View rendering, localization, and translation helpers |
| [`routed_http`](https://github.com/kingwill101/routed/tree/master/packages/routed_http) | `0.1.3` | JSON/XML binding, multipart, negotiation, buffered gzip compression, SSE, and conditional requests |
| [`routed_hotwire`](https://github.com/kingwill101/routed/tree/master/packages/routed_hotwire) | `0.1.7` | Turbo and Stimulus response helpers |
| [`routed_validation`](https://github.com/kingwill101/routed/tree/master/packages/routed_validation) | `0.1.1` | Validation rules and validation utilities |
| [`routed_openapi`](https://github.com/kingwill101/routed/tree/master/packages/routed_openapi) | `0.1.1` | OpenAPI route manifests plus OpenAPI 3.1 generation from composed auth plugins |

## Host runtimes

| Package | Version | Role |
| --- | --- | --- |
| [`routed_io`](https://github.com/kingwill101/routed/tree/master/packages/routed_io) | `0.1.2` | `dart:io` server transport |
| [`routed_node`](https://github.com/kingwill101/routed/tree/master/packages/routed_node) | `0.2.1` | Node.js, Bun, Deno, and Fetch/Cloudflare edge transports and bindings |
| [`server_native`](https://github.com/kingwill101/routed/tree/master/packages/server_native) | `0.1.7` | Rust-backed native HTTP server runtime |

## Server runtimes and contracts

| Package | Version | Role |
| --- | --- | --- |
| [`server_contracts`](https://github.com/kingwill101/routed/tree/master/packages/server_contracts) | `0.1.1` | Framework-agnostic interfaces and value contracts |
| [`server_auth`](https://github.com/kingwill101/routed/tree/master/packages/server_auth) | `0.2.1` | Typed auth plugins, stores, clients, OAuth/OIDC, WebAuthn, deployment presets, and conformance support |
| [`server_cache`](https://github.com/kingwill101/routed/tree/master/packages/server_cache) | `0.2.1` | Framework-agnostic cache stores and repositories |
| [`server_sessions`](https://github.com/kingwill101/routed/tree/master/packages/server_sessions) | `0.1.2` | Framework-agnostic session runtime |
| [`server_storage`](https://github.com/kingwill101/routed/tree/master/packages/server_storage) | `0.1.3` | Framework-agnostic storage runtime |
| [`server_rate_limit`](https://github.com/kingwill101/routed/tree/master/packages/server_rate_limit) | `0.1.2` | Framework-agnostic rate-limit runtime |

## Tooling and testing

| Package | Version | Role |
| --- | --- | --- |
| [`routed_cli`](https://github.com/kingwill101/routed/tree/master/packages/routed_cli) | `0.4.0` | Project commands, configuration, development, and deployment tooling |
| [`routed_analyzer`](https://github.com/kingwill101/routed/tree/master/packages/routed_analyzer) | `0.1.2` | Analyzer plugin and Routed lint rules |
| [`routed_openapi_builder`](https://github.com/kingwill101/routed/tree/master/packages/routed_openapi_builder) | `0.1.1` | Build-time OpenAPI artifact generation |
| [`routed_testing`](https://github.com/kingwill101/routed/tree/master/packages/server_testing/routed_testing) | `0.4.1` | Routed adapter for the upstream `server_testing` harness |

## Choosing a package

Start with `routed` for a standard application. Use `routed_core` plus the
feature adapters you need when minimizing runtime dependencies or composing
providers explicitly. The `server_*` packages are framework-agnostic runtimes;
use the matching `routed_*` adapter when the code runs inside a Routed engine.

The package READMEs document provider initialization and middleware setup for
each feature package.
