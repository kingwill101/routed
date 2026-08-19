/// Configuration for the in-memory reference platform.
final class PlatformConfig {
  const PlatformConfig({
    required this.apiToken,
    required this.defaultTenant,
    required this.defaultNamespace,
  });

  final String apiToken;
  final String defaultTenant;
  final String defaultNamespace;
}
