library;

import 'dart:io';

import 'bundle_detector.dart';

/// Defines SSR configuration and helpers for Inertia.
///
/// ```dart
/// final settings = InertiaSsrSettings(
///   enabled: true,
///   endpoint: Uri.parse('http://127.0.0.1:13714/render'),
///   bundle: 'bootstrap/ssr/ssr.mjs',
/// );
/// ```
class InertiaSsrSettings {
  /// Creates SSR settings with optional overrides.
  const InertiaSsrSettings({
    this.enabled = false,
    this.endpoint,
    this.healthEndpoint,
    this.shutdownEndpoint,
    this.bundle,
    this.ensureBundleExists = true,
    this.runtime = 'node',
    this.runtimeArgs = const [],
    this.bundleCandidates = const [],
    this.workingDirectory,
    this.environment = const {},
  });

  /// Whether SSR is enabled.
  final bool enabled;

  /// The SSR render endpoint, if configured.
  final Uri? endpoint;

  /// Optional health check endpoint override.
  final Uri? healthEndpoint;

  /// Optional shutdown endpoint override.
  final Uri? shutdownEndpoint;

  /// The SSR bundle path, if configured.
  final String? bundle;

  /// Whether to ensure the bundle exists on startup.
  final bool ensureBundleExists;

  /// The runtime used to execute the SSR bundle.
  final String runtime;

  /// Arguments passed to the SSR runtime.
  final List<String> runtimeArgs;

  /// Candidate bundle paths used by [SsrBundleDetector].
  final List<String> bundleCandidates;

  /// Working directory used by the SSR process.
  final Directory? workingDirectory;

  /// Environment variables passed to the SSR process.
  final Map<String, String> environment;

  /// Returns a bundle detector based on this configuration.
  SsrBundleDetector bundleDetector() {
    return SsrBundleDetector(
      bundle: bundle,
      workingDirectory: workingDirectory,
      candidates: bundleCandidates,
    );
  }

  /// Resolves the health endpoint based on [endpoint].
  Uri? resolveHealthEndpoint() {
    if (healthEndpoint != null) return healthEndpoint;
    if (endpoint == null) return null;
    return endpoint!.resolve('/health');
  }

  /// Resolves the shutdown endpoint based on [endpoint].
  Uri? resolveShutdownEndpoint() {
    if (shutdownEndpoint != null) return shutdownEndpoint;
    if (endpoint == null) return null;
    return endpoint!.resolve('/shutdown');
  }

  /// Resolves the render endpoint, appending `/render` when needed.
  Uri? resolveRenderEndpoint() {
    if (endpoint == null) return null;
    if (endpoint!.path.endsWith('/render')) return endpoint;
    return endpoint!.resolve('/render');
  }

  /// Returns a copy of these settings with updated values.
  ///
  /// ```dart
  /// final updated = settings.copyWith(enabled: true);
  /// ```
  InertiaSsrSettings copyWith({
    bool? enabled,
    Uri? endpoint,
    Uri? healthEndpoint,
    Uri? shutdownEndpoint,
    String? bundle,
    bool? ensureBundleExists,
    String? runtime,
    List<String>? runtimeArgs,
    List<String>? bundleCandidates,
    Directory? workingDirectory,
    Map<String, String>? environment,
  }) {
    return InertiaSsrSettings(
      enabled: enabled ?? this.enabled,
      endpoint: endpoint ?? this.endpoint,
      healthEndpoint: healthEndpoint ?? this.healthEndpoint,
      shutdownEndpoint: shutdownEndpoint ?? this.shutdownEndpoint,
      bundle: bundle ?? this.bundle,
      ensureBundleExists: ensureBundleExists ?? this.ensureBundleExists,
      runtime: runtime ?? this.runtime,
      runtimeArgs: runtimeArgs ?? this.runtimeArgs,
      bundleCandidates: bundleCandidates ?? this.bundleCandidates,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      environment: environment ?? this.environment,
    );
  }
}
