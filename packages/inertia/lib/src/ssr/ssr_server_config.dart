library;

import 'dart:io';

import 'bundle_detector.dart';
import 'inertia_ssr_settings.dart';

/// Defines configuration needed to start a local SSR server process.
///
/// ```dart
/// final config = SsrServerConfig.fromSettings(settings);
/// final bundle = config.resolveBundle();
/// ```
class SsrServerConfig {
  /// Creates a server configuration.
  const SsrServerConfig({
    required this.runtime,
    this.bundle,
    this.runtimeArgs = const [],
    this.bundleCandidates = const [],
    this.workingDirectory,
    this.environment = const {},
  });

  /// Creates a server configuration from [settings].
  factory SsrServerConfig.fromSettings(InertiaSsrSettings settings) {
    return SsrServerConfig(
      runtime: settings.runtime,
      bundle: settings.bundle,
      runtimeArgs: settings.runtimeArgs,
      bundleCandidates: settings.bundleCandidates,
      workingDirectory: settings.workingDirectory,
      environment: settings.environment,
    );
  }

  /// The runtime used to execute the SSR bundle.
  final String runtime;

  /// The SSR bundle path, if configured.
  final String? bundle;

  /// Arguments passed to the SSR runtime.
  final List<String> runtimeArgs;

  /// Candidate bundle paths used for resolution.
  final List<String> bundleCandidates;

  /// Working directory for the SSR process.
  final Directory? workingDirectory;

  /// Environment variables for the SSR process.
  final Map<String, String> environment;

  /// Resolves the SSR bundle path, if present.
  String? resolveBundle() {
    return SsrBundleDetector(
      bundle: bundle,
      workingDirectory: workingDirectory,
      candidates: bundleCandidates,
    ).detect();
  }
}
