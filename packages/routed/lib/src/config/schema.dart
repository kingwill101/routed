import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/provider/provider.dart';

/// Extensions on [Schema] to provide a more fluent API for Routed configuration.
extension RoutedSchemaExtension on Schema {
  /// Returns a new [Schema] with the `default` keyword set to [defaultValue].
  Schema withDefault(Object? defaultValue) {
    return Schema.fromMap({...value, 'default': defaultValue});
  }

  /// Returns a new [Schema] with the `examples` keyword set to [examples].
  Schema withExamples(List<Object?> examples) {
    return Schema.fromMap({...value, 'examples': examples});
  }

  /// Returns a new [Schema] with the `metadata` keyword set.
  Schema withMetadata(Map<String, Object?> metadata) {
    return Schema.fromMap({...value, 'metadata': metadata});
  }
}

/// A specialized builder for Routed configuration schemas.
class ConfigSchema {
  /// Creates an object schema for a configuration section.
  static Schema object({
    String? title,
    String? description,
    Map<String, Schema>? properties,
    List<String>? required,
    Object? additionalProperties,
    Map<String, dynamic>? defaultValue,
  }) {
    final Map<String, dynamic> schemaMap = {
      'type': 'object',
      'title': ?title,
      'description': ?description,
      'properties': ?properties?.map(
        (key, value) => MapEntry(key, value.value),
      ),
      'required': ?required,
    };

    if (additionalProperties != null) {
      if (additionalProperties is bool) {
        schemaMap['additionalProperties'] = additionalProperties;
      } else if (additionalProperties is Schema) {
        schemaMap['additionalProperties'] =
            (additionalProperties as Schema).value;
      } else if (additionalProperties is Map) {
        schemaMap['additionalProperties'] = additionalProperties;
      }
    } else {
      schemaMap['additionalProperties'] = false;
    }

    var schema = Schema.fromMap(schemaMap);
    if (defaultValue != null) {
      schema = schema.withDefault(defaultValue);
    }
    return schema;
  }

  /// Creates a string schema with an optional default value.
  static Schema string({
    String? title,
    String? description,
    String? defaultValue,
    int? minLength,
    int? maxLength,
    String? pattern,
    String? format,
    List<String>? options,
  }) {
    var schema = S.string(
      title: title,
      description: description,
      minLength: minLength,
      maxLength: maxLength,
      pattern: pattern,
      format: format,
    );
    if (defaultValue != null) {
      schema = schema.withDefault(defaultValue);
    }
    if (options != null) {
      schema = Schema.fromMap({...schema.value, 'enum': options});
    }
    return schema;
  }

  /// Creates a boolean schema with an optional default value.
  static Schema boolean({
    String? title,
    String? description,
    bool? defaultValue,
  }) {
    var schema = S.boolean(title: title, description: description);
    if (defaultValue != null) {
      schema = schema.withDefault(defaultValue);
    }
    return schema;
  }

  /// Creates an integer schema with an optional default value.
  static Schema integer({
    String? title,
    String? description,
    int? defaultValue,
    int? minimum,
    int? maximum,
  }) {
    var schema = S.integer(
      title: title,
      description: description,
      minimum: minimum,
      maximum: maximum,
    );
    if (defaultValue != null) {
      schema = schema.withDefault(defaultValue);
    }
    return schema;
  }

  /// Creates a number schema with an optional default value.
  static Schema number({
    String? title,
    String? description,
    double? defaultValue,
    double? minimum,
    double? maximum,
  }) {
    var schema = S.number(
      title: title,
      description: description,
      minimum: minimum,
      maximum: maximum,
    );
    if (defaultValue != null) {
      schema = schema.withDefault(defaultValue);
    }
    return schema;
  }

  /// Creates a duration schema (stored as string) with an optional default value.
  static Schema duration({
    String? title,
    String? description,
    String? defaultValue,
  }) {
    return string(
      title: title,
      description: description,
      defaultValue: defaultValue,
      format: 'duration',
    );
  }

  /// Creates a list schema with an optional default value.
  static Schema list({
    String? title,
    String? description,
    List<Object?>? defaultValue,
    Schema? items,
    int? minItems,
    int? maxItems,
    bool uniqueItems = false,
  }) {
    var schema = S.list(
      title: title,
      description: description,
      items: items,
      minItems: minItems,
      maxItems: maxItems,
      uniqueItems: uniqueItems,
    );
    if (defaultValue != null) {
      schema = schema.withDefault(defaultValue);
    }
    return schema;
  }

  /// Extracts default values from a [Schema] as a map.
  static Map<String, dynamic> extractDefaults(Schema schema) {
    final result = <String, dynamic>{};
    final value = schema.value;

    // Check if it's an object type schema
    if (value['type'] == JsonType.object.typeName ||
        value.containsKey('properties')) {
      final properties = value['properties'];
      if (properties is Map) {
        for (final entry in properties.entries) {
          final propSchema = Schema.fromMap(
            entry.value as Map<String, Object?>,
          );
          final defaultValue = propSchema.defaultValue;
          if (defaultValue != null) {
            result[entry.key as String] = defaultValue;
          } else {
            final nestedDefaults = extractDefaults(propSchema);
            if (nestedDefaults.isNotEmpty) {
              result[entry.key as String] = nestedDefaults;
            }
          }
        }
      }
    }
    return result;
  }

  /// Converts a [Schema] into a list of [ConfigDocEntry]s.
  static List<ConfigDocEntry> toDocEntries(Schema schema, {String? pathBase}) {
    final entries = <ConfigDocEntry>[];
    final value = schema.value;
    final root = pathBase ?? '';

    String join(String segment) => root.isEmpty ? segment : '$root.$segment';

    // Handle object properties
    if (value['type'] == JsonType.object.typeName ||
        value.containsKey('properties')) {
      final properties = value['properties'];
      if (properties is Map) {
        for (final entry in properties.entries) {
          final propName = entry.key as String;
          final propSchema = Schema.fromMap(
            entry.value as Map<String, Object?>,
          );
          final fullPath = join(propName);

          final metadata = propSchema['metadata'];
          entries.add(
            ConfigDocEntry(
              path: fullPath,
              description: propSchema.description,
              type: propSchema.type is String
                  ? propSchema.type as String
                  : null,
              defaultValue: propSchema.defaultValue,
              deprecated: propSchema.deprecated ?? false,
              metadata: metadata is Map<String, Object?> ? metadata : const {},
            ),
          );

          // Recurse into nested objects
          entries.addAll(toDocEntries(propSchema, pathBase: fullPath));
        }
      }
    }

    return entries;
  }
}
