import 'package:routed_core/routed_core.dart'
    show ProviderRegistry, TypedConfigurationProvider;

/// Metadata describing a registered service provider.
///
/// Configuration is deliberately represented by its Dart type rather than a
/// generated schema or a collection of string paths. The provider instance is
/// the source of truth for configuration and performs its own validation at
/// engine startup.
class ProviderMetadata {
  ProviderMetadata({
    required this.id,
    required this.description,
    required this.providerType,
    this.configurationType,
  });

  factory ProviderMetadata.fromJson(Map<String, Object?> json) {
    return ProviderMetadata(
      id: json['id']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      providerType: json['providerType']?.toString() ?? '',
      configurationType: json['configurationType']?.toString(),
    );
  }

  final String id;
  final String description;
  final String providerType;
  final String? configurationType;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'description': description,
      'providerType': providerType,
      if (configurationType != null) 'configurationType': configurationType,
    };
  }
}

/// Collects registered providers and their typed configuration metadata.
List<ProviderMetadata> inspectProviders() {
  final providers = <ProviderMetadata>[];
  for (final registration in ProviderRegistry.instance.registrations) {
    final provider = registration.factory();
    final typedProvider = provider is TypedConfigurationProvider
        ? provider as TypedConfigurationProvider
        : null;
    providers.add(
      ProviderMetadata(
        id: registration.id,
        description: registration.description,
        providerType: provider.runtimeType.toString(),
        configurationType: typedProvider?.configurationType.toString(),
      ),
    );
  }
  return providers;
}
