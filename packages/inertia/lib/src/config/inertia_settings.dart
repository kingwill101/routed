library;

import '../ssr/inertia_ssr_settings.dart';

/// Defines configuration settings for the Inertia core package.
///
/// ```dart
/// final settings = InertiaSettings(
///   version: '1.0.0',
///   ssrEnabled: true,
///   ssrEndpoint: Uri.parse('http://127.0.0.1:13714/render'),
/// );
/// ```
class InertiaSettings {
  /// Creates configuration settings with optional SSR overrides.
  InertiaSettings({
    this.version = '',
    bool ssrEnabled = false,
    Uri? ssrEndpoint,
    InertiaSsrSettings? ssr,
  }) : ssr =
           ssr ??
           InertiaSsrSettings(enabled: ssrEnabled, endpoint: ssrEndpoint),
       ssrEnabled = ssr?.enabled ?? ssrEnabled,
       ssrEndpoint = ssr?.endpoint ?? ssrEndpoint;

  /// The asset version string.
  final String version;

  /// Whether SSR is enabled.
  final bool ssrEnabled;

  /// The SSR render endpoint, if configured.
  final Uri? ssrEndpoint;

  /// The detailed SSR settings.
  final InertiaSsrSettings ssr;

  /// Returns a copy of these settings with updated values.
  ///
  /// ```dart
  /// final updated = settings.copyWith(version: '2.0.0');
  /// ```
  InertiaSettings copyWith({
    String? version,
    bool? ssrEnabled,
    Uri? ssrEndpoint,
    InertiaSsrSettings? ssr,
  }) {
    final resolvedSsr =
        ssr ??
        InertiaSsrSettings(
          enabled: ssrEnabled ?? this.ssr.enabled,
          endpoint: ssrEndpoint ?? this.ssr.endpoint,
          healthEndpoint: this.ssr.healthEndpoint,
          shutdownEndpoint: this.ssr.shutdownEndpoint,
          bundle: this.ssr.bundle,
          ensureBundleExists: this.ssr.ensureBundleExists,
          runtime: this.ssr.runtime,
          runtimeArgs: this.ssr.runtimeArgs,
          bundleCandidates: this.ssr.bundleCandidates,
          workingDirectory: this.ssr.workingDirectory,
          environment: this.ssr.environment,
        );
    return InertiaSettings(
      version: version ?? this.version,
      ssrEnabled: resolvedSsr.enabled,
      ssrEndpoint: resolvedSsr.endpoint,
      ssr: resolvedSsr,
    );
  }
}
