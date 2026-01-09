import 'package:json_schema_builder/json_schema_builder.dart';
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

  factory ConfigFieldMetadata.fromJson(Map<String, Object?> json) {
    final options = (json['options'] as List?)
        ?.map((value) => value.toString())
        .toList();
    final rawMetadata = json['metadata'] as Map?;
    return ConfigFieldMetadata(
      path: json['path']?.toString() ?? '',
      type: json['type']?.toString(),
      description: json['description']?.toString(),
      defaultValue: json['default'],
      deprecated: json['deprecated'] as bool? ?? false,
      options: options ?? const <String>[],
      metadata:
          rawMetadata?.map((key, value) => MapEntry('$key', value)) ??
          const <String, Object?>{},
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
    this.schemas = const {},
  });

  factory ProviderMetadata.fromJson(Map<String, Object?> json) {
    final rawDefaults = json['defaults'] as Map?;
    final defaults =
        rawDefaults?.map((key, value) => MapEntry('$key', value)) ??
        const <String, dynamic>{};
    final rawFields = json['fields'] as List?;
    final fields =
        rawFields
            ?.whereType<Map>()
            .map(
              (entry) => ConfigFieldMetadata.fromJson(
                entry.map((key, value) => MapEntry('$key', value)),
              ),
            )
            .toList() ??
        const <ConfigFieldMetadata>[];
    final rawSchemas = json['schemas'] as Map?;
    final schemas = <String, Schema>{};
    if (rawSchemas != null) {
      for (final entry in rawSchemas.entries) {
        final value = entry.value;
        if (value is Map) {
          schemas[entry.key.toString()] = Schema.fromMap(
            value.map((key, schemaValue) => MapEntry('$key', schemaValue)),
          );
        }
      }
    }
    return ProviderMetadata(
      id: json['id']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      providerType: json['providerType']?.toString() ?? '',
      configSource: json['configSource']?.toString() ?? '',
      defaults: defaults,
      fields: fields,
      schemas: schemas,
    );
  }

  final String id;
  final String description;
  final String providerType;
  final String configSource;
  final Map<String, dynamic> defaults;
  final List<ConfigFieldMetadata> fields;
  final Map<String, Schema> schemas;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'description': description,
      'providerType': providerType,
      'configSource': configSource,
      'defaults': defaults,
      'fields': fields.map((field) => field.toJson()).toList(),
      if (schemas.isNotEmpty)
        'schemas': schemas.map((k, v) => MapEntry(k, v.value)),
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
          schemas: snapshot.schemas,
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
