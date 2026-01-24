/// Configuration settings for the Inertia core package
class InertiaSettings {
  const InertiaSettings({
    this.version = '',
    this.ssrEnabled = false,
    this.ssrEndpoint,
  });
  final String version;
  final bool ssrEnabled;
  final Uri? ssrEndpoint;

  InertiaSettings copyWith({
    String? version,
    bool? ssrEnabled,
    Uri? ssrEndpoint,
  }) {
    return InertiaSettings(
      version: version ?? this.version,
      ssrEnabled: ssrEnabled ?? this.ssrEnabled,
      ssrEndpoint: ssrEndpoint ?? this.ssrEndpoint,
    );
  }
}
