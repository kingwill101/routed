/// Build-runner integration for generating static OpenAPI artifacts for Routed.
///
/// The builder consumes the authoritative route manifest produced by
/// `routed_cli openapi generate`. It writes an OpenAPI 3.1 JSON document and a
/// Dart controller that can serve that document from a Routed application.
///
/// Add the package as a development dependency and configure it in
/// `build.yaml`:
///
/// ```yaml
/// targets:
///   $default:
///     builders:
///       routed_openapi_builder|openapi:
///         options:
///           title: Accounts API
///           version: 1.0.0
///           serve_path: /openapi.json
/// ```
///
/// Then generate the manifest and run the builder:
///
/// ```bash
/// dart run routed_cli openapi generate
/// dart run build_runner build --delete-conflicting-outputs
/// ```
///
/// The generated files are `lib/generated/openapi.json` and
/// `lib/generated/openapi_controller.g.dart`. This package is build-time
/// tooling; it does not initialize an engine or register runtime providers.
library;

export 'src/builder.dart';
