# Routed package catalog

Package inventory for the Routed ecosystem. Versions below match the package
manifests in this checkout as of 2026-08-15.

## Framework and feature packages

| Package | Version | Role |
| --- | --- | --- |
| [`routed`](https://github.com/kingwill101/routed/tree/master/packages/routed) | `0.3.3` | Batteries-included framework facade and official provider registry |
| [`routed_core`](https://github.com/kingwill101/routed/tree/master/packages/routed_core) | `0.3.3` | Slim engine, routing, contexts, configuration, and lifecycle |
| [`routed_auth`](https://github.com/kingwill101/routed/tree/master/packages/routed_auth) | `0.1.0` | Routed authentication and authorization integration |
| [`routed_cache`](https://github.com/kingwill101/routed/tree/master/packages/routed_cache) | `0.1.0` | Cache services and context helpers for Routed |
| [`routed_logging`](https://github.com/kingwill101/routed/tree/master/packages/routed_logging) | `0.1.0` | HTTP logging provider and request logger helpers |
| [`routed_observability`](https://github.com/kingwill101/routed/tree/master/packages/routed_observability) | `0.1.0` | Health, metrics, tracing, and error observation |
| [`routed_rate_limit`](https://github.com/kingwill101/routed/tree/master/packages/routed_rate_limit) | `0.1.0` | Rate-limit service and middleware integration |
| [`routed_security`](https://github.com/kingwill101/routed/tree/master/packages/routed_security) | `0.1.0` | CORS middleware plus IP filtering, network matching, and trusted-proxy primitives |
| [`routed_sessions`](https://github.com/kingwill101/routed/tree/master/packages/routed_sessions) | `0.1.0` | Session stores, middleware, and context helpers |
| [`routed_storage`](https://github.com/kingwill101/routed/tree/master/packages/routed_storage) | `0.1.0` | Storage managers, disks, static-mount provider, middleware, and filesystem helpers |
| [`routed_views`](https://github.com/kingwill101/routed/tree/master/packages/routed_views) | `0.1.0` | View rendering, localization, and translation helpers |
| [`routed_http`](https://github.com/kingwill101/routed/tree/master/packages/routed_http) | `0.1.0` | Binding, multipart, negotiation, buffered gzip compression, SSE, and conditional requests |
| [`routed_hotwire`](https://github.com/kingwill101/routed/tree/master/packages/routed_hotwire) | `0.1.2` | Turbo and Stimulus response helpers |
| [`routed_validation`](https://github.com/kingwill101/routed/tree/master/packages/routed_validation) | `0.1.0` | Validation rules and validation utilities |
| [`routed_openapi`](https://github.com/kingwill101/routed/tree/master/packages/routed_openapi) | `0.1.0` | OpenAPI route metadata and manifest generation |

## Host runtimes

| Package | Version | Role |
| --- | --- | --- |
| [`routed_io`](https://github.com/kingwill101/routed/tree/master/packages/routed_io) | `0.1.0` | `dart:io` server transport |
| [`routed_node`](https://github.com/kingwill101/routed/tree/master/packages/routed_node) | `0.1.0` | Node.js, Bun, Deno, and Fetch-based edge transports |
| [`server_native`](https://github.com/kingwill101/routed/tree/master/packages/server_native) | `0.1.3+1` | Rust-backed native HTTP server runtime |

## Server runtimes and contracts

| Package | Version | Role |
| --- | --- | --- |
| [`server_contracts`](https://github.com/kingwill101/routed/tree/master/packages/server_contracts) | `0.1.0` | Framework-agnostic interfaces and value contracts |
| [`server_auth`](https://github.com/kingwill101/routed/tree/master/packages/server_auth) | `0.1.0` | Authentication providers, JWT, OAuth, and authorization primitives |
| [`server_cache`](https://github.com/kingwill101/routed/tree/master/packages/server_cache) | `0.1.0` | Framework-agnostic cache stores and repositories |
| [`server_sessions`](https://github.com/kingwill101/routed/tree/master/packages/server_sessions) | `0.1.0` | Framework-agnostic session runtime |
| [`server_storage`](https://github.com/kingwill101/routed/tree/master/packages/server_storage) | `0.1.0` | Framework-agnostic storage runtime |
| [`server_rate_limit`](https://github.com/kingwill101/routed/tree/master/packages/server_rate_limit) | `0.1.0` | Framework-agnostic rate-limit runtime |

## Tooling and testing

| Package | Version | Role |
| --- | --- | --- |
| [`routed_cli`](https://github.com/kingwill101/routed/tree/master/packages/routed_cli) | `0.1.0` | Project commands, configuration, development, and deployment tooling |
| [`routed_analyzer`](https://github.com/kingwill101/routed/tree/master/packages/routed_analyzer) | `0.1.0` | Analyzer plugin and Routed lint rules |
| [`routed_openapi_builder`](https://github.com/kingwill101/routed/tree/master/packages/routed_openapi_builder) | `0.1.0` | Build-time OpenAPI artifact generation |
| [`routed_testing`](https://github.com/kingwill101/routed/tree/master/packages/server_testing/routed_testing) | `0.3.3` | Routed adapter for the upstream `server_testing` harness |

## Choosing a package

Start with `routed` for a standard application. Use `routed_core` plus the
feature adapters you need when minimizing runtime dependencies or composing
providers explicitly. The `server_*` packages are framework-agnostic runtimes;
use the matching `routed_*` adapter when the code runs inside a Routed engine.

The package READMEs document provider initialization and middleware setup for
each feature package.
