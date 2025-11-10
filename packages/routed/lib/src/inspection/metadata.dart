import 'package:routed/src/provider/provider.dart';

import '../engine/providers/registry.dart';

/// Metadata describing a single configuration field contributed by a provider.
class ConfigFieldMetadata {
  ConfigFieldMetadata({
    required this.path,
    this.type,
    this.description,
    this.defaultValue,
    this.deprecated = false,
    this.options = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  factory ConfigFieldMetadata.fromDoc(ConfigDocEntry entry) {
    final options = entry.resolveOptions() ?? const <String>[];
    return ConfigFieldMetadata(
      path: entry.path,
      type: entry.type,
      description: entry.description,
      defaultValue: entry.defaultValue,
      deprecated: entry.deprecated,
      options: options,
      metadata: entry.metadata,
    );
  }

  final String path;
  final String? type;
  final String? description;
  final Object? defaultValue;
  final bool deprecated;
  final List<String> options;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      if (type != null) 'type': type,
      if (description != null) 'description': description,
      if (defaultValue != null) 'default': defaultValue,
      if (deprecated) 'deprecated': true,
      if (options.isNotEmpty) 'options': options,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

/// Metadata describing a registered service provider.
class ProviderMetadata {
  ProviderMetadata({
    required this.id,
    required this.description,
    required this.providerType,
    required this.configSource,
    required this.defaults,
    required this.fields,
  });

  final String id;
  final String description;
  final String providerType;
  final String configSource;
  final Map<String, dynamic> defaults;
  final List<ConfigFieldMetadata> fields;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'description': description,
      'providerType': providerType,
      'configSource': configSource,
      'defaults': defaults,
      'fields': fields.map((field) => field.toJson()).toList(),
    };
  }
}

/// Collects registered providers and their configuration metadata.
List<ProviderMetadata> inspectProviders() {
  final providers = <ProviderMetadata>[];
  for (final registration in ProviderRegistry.instance.registrations) {
    final provider = registration.factory();
    if (provider is ProvidesDefaultConfig) {
      final snapshot = provider.defaultConfig.snapshot();
      final fields = snapshot.docs
          .map((doc) => ConfigFieldMetadata.fromDoc(doc))
          .toList(growable: false);
      providers.add(
        ProviderMetadata(
          id: registration.id,
          description: registration.description,
          providerType: provider.runtimeType.toString(),
          configSource: provider.configSource,
          defaults: snapshot.values,
          fields: fields,
        ),
      );
    } else {
      providers.add(
        ProviderMetadata(
          id: registration.id,
          description: registration.description,
          providerType: provider.runtimeType.toString(),
          configSource: provider.runtimeType.toString(),
          defaults: const {},
          fields: const [],
        ),
      );
    }
  }
  return providers;
}
