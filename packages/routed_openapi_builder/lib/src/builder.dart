import 'dart:async';

import 'package:build/build.dart';
import 'package:routed_openapi/routed_openapi.dart' as routed_openapi;

/// Build-time OpenAPI builder for Routed.
///
/// This is a small public wrapper around the implementation that lives in
/// `routed_openapi`, so apps can depend on `routed_openapi_builder` as their
/// build-time integration package.
class OpenApiBuilder implements Builder {
  OpenApiBuilder([Map<String, dynamic>? config])
    : _delegate = routed_openapi.openApiBuilder(
        BuilderOptions(config ?? const <String, dynamic>{}),
      );

  final Builder _delegate;

  @override
  Map<String, List<String>> get buildExtensions => _delegate.buildExtensions;

  @override
  FutureOr<void> build(BuildStep buildStep) => _delegate.build(buildStep);
}

Builder openApiBuilder(BuilderOptions options) =>
    OpenApiBuilder(options.config);
