/// Provider metadata inspection for Routed tooling.
///
/// The inspection API is intended for diagnostics, generated tooling, and
/// development-time screens. It reports the registrations currently held by
/// [ProviderRegistry] and preserves the provider's typed configuration as a
/// runtime type name; it does not serialize configuration values.
library;

import 'package:routed_core/routed_core.dart'
    show ProviderRegistry, TypedConfigurationProvider;

/// Metadata describing a registered service provider.
///
/// Configuration is deliberately represented by its Dart type rather than a
/// generated schema or a collection of string paths. The provider instance is
/// the source of truth for configuration and performs its own validation at
/// engine startup.
class ProviderMetadata {
  /// Creates metadata for a registered provider.
  ProviderMetadata({
    required this.id,
    required this.description,
    required this.providerType,
    this.configurationType,
  });

  /// Creates metadata from a serialized JSON object.
  ///
  /// Missing fields are represented by empty strings, except for the optional
  /// [configurationType] field. Unknown keys are ignored.
  factory ProviderMetadata.fromJson(Map<String, Object?> json) {
    return ProviderMetadata(
      id: json['id']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      providerType: json['providerType']?.toString() ?? '',
      configurationType: json['configurationType']?.toString(),
    );
  }

  /// The stable identifier assigned to the provider registration.
  final String id;

  /// The human-readable description supplied by the provider registration.
  final String description;

  /// The runtime type name of the provider instance.
  final String providerType;

  /// The runtime type name of the provider's typed configuration, if any.
  final String? configurationType;

  /// Serializes this metadata to a JSON-compatible map.
  ///
  /// The map contains the stable provider [id], description, provider type,
  /// and, when available, the typed configuration type name.
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
///
/// The returned list reflects the registrations currently held by
/// [ProviderRegistry] in registration order. Each registration factory is
/// invoked to determine the provider and configuration type names, so callers
/// should use this during tooling or diagnostics rather than as a substitute
/// for application startup.
///
/// A provider that does not implement [TypedConfigurationProvider] has a null
/// [ProviderMetadata.configurationType].
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
