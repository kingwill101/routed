/// Converts validation pipe rules (e.g. `'required|string|min:2'`) into
/// JSON Schema (Draft 2020-12) maps compatible with OpenAPI 3.1.
///
/// This bridge allows route schemas defined with pipe rules to automatically
/// produce JSON Schema for both runtime validation and OpenAPI generation.
///
/// ```dart
/// final schema = PipeRuleSchemaConverter.convertRules({
///   'name': 'required|string|min:2|max:100',
///   'email': 'required|email',
///   'age': 'integer|min:0|max:150',
/// });
/// // Produces a JSON Schema object with properties, required list, etc.
/// ```
library;

import 'package:json_schema_builder/json_schema_builder.dart';

/// Converts validation pipe-rule maps into JSON Schema objects.
class PipeRuleSchemaConverter {
  const PipeRuleSchemaConverter._();

  /// Converts a map of field names to pipe-rule strings into a JSON Schema
  /// object schema with properties and required fields.
  ///
  /// Returns the raw `Map<String, Object?>` representation of the schema.
  static Map<String, Object?> convertRules(Map<String, String> rules) {
    final properties = <String, Schema>{};
    final required = <String>[];

    for (final entry in rules.entries) {
      final field = entry.key;
      final ruleString = entry.value;
      final parsed = _parseRuleString(ruleString);

      if (parsed.isRequired) {
        required.add(field);
      }

      properties[field] = _buildPropertySchema(parsed);
    }

    final schema = Schema.object(
      properties: properties,
      required: required.isEmpty ? null : required,
    );

    return schema.value;
  }

  /// Converts a single field's pipe-rule string into a JSON Schema.
  ///
  /// Useful for parameter schemas where only one field is described.
  static Map<String, Object?> convertSingleRule(String ruleString) {
    final parsed = _parseRuleString(ruleString);
    return _buildPropertySchema(parsed).value;
  }

  /// Parses a pipe-delimited rule string into structured rule data.
  static _ParsedRules _parseRuleString(String ruleString) {
    final parts = ruleString.split('|');
    final result = _ParsedRules();

    for (final part in parts) {
      final colonIndex = part.indexOf(':');
      final ruleName = colonIndex >= 0 ? part.substring(0, colonIndex) : part;
      final options = colonIndex >= 0
          ? part.substring(colonIndex + 1).split(',')
          : null;

      switch (ruleName) {
        // Type rules
        case 'string':
          result.type = _SchemaType.string;
        case 'int' || 'integer':
          result.type = _SchemaType.integer;
        case 'double' || 'numeric' || 'decimal':
          result.type = _SchemaType.number;
        case 'boolean':
          result.type = _SchemaType.boolean;
        case 'array' || 'list':
          result.type = _SchemaType.array;
        case 'json':
          result.type = _SchemaType.object;

        // Presence rules
        case 'required':
          result.isRequired = true;
        case 'nullable':
          result.isNullable = true;

        // String length / numeric value constraints
        case 'min':
          if (options != null && options.isNotEmpty) {
            result.min = num.tryParse(options[0]);
          }
        case 'max':
          if (options != null && options.isNotEmpty) {
            result.max = num.tryParse(options[0]);
          }
        case 'min_length' || 'minLength':
          if (options != null && options.isNotEmpty) {
            result.minLength = int.tryParse(options[0]);
          }
        case 'max_length' || 'maxLength':
          if (options != null && options.isNotEmpty) {
            result.maxLength = int.tryParse(options[0]);
          }
        case 'between':
          if (options != null && options.length >= 2) {
            result.min = num.tryParse(options[0]);
            result.max = num.tryParse(options[1]);
          }

        // Format rules
        case 'email':
          result.type ??= _SchemaType.string;
          result.format = 'email';
        case 'url' || 'active_url':
          result.type ??= _SchemaType.string;
          result.format = 'uri';
        case 'uuid':
          result.type ??= _SchemaType.string;
          result.format = 'uuid';
        case 'ip':
          result.type ??= _SchemaType.string;
          result.format = 'ip-address';
        case 'ipv4':
          result.type ??= _SchemaType.string;
          result.format = 'ipv4';
        case 'ipv6':
          result.type ??= _SchemaType.string;
          result.format = 'ipv6';
        case 'date':
          result.type ??= _SchemaType.string;
          result.format = 'date';
        case 'date_format':
          result.type ??= _SchemaType.string;
          result.format = 'date-time';

        // Enum rules
        case 'in':
          if (options != null && options.isNotEmpty) {
            result.enumValues = options;
          }
        case 'not_in':
          // OpenAPI doesn't have a direct "not in" — we skip this
          break;

        // Pattern rules
        case 'alpha':
          result.type ??= _SchemaType.string;
          result.pattern = r'^[a-zA-Z]+$';
        case 'alpha_num':
          result.type ??= _SchemaType.string;
          result.pattern = r'^[a-zA-Z0-9]+$';
        case 'alpha_dash':
          result.type ??= _SchemaType.string;
          result.pattern = r'^[a-zA-Z0-9_-]+$';
        case 'slug':
          result.type ??= _SchemaType.string;
          result.pattern = r'^[a-z0-9]+(?:-[a-z0-9]+)*$';
        case 'ascii':
          result.type ??= _SchemaType.string;
          result.pattern = r'^[\x00-\x7F]+$';
        case 'hex_color':
          result.type ??= _SchemaType.string;
          result.pattern = r'^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$';
        case 'lowercase':
          result.type ??= _SchemaType.string;
          result.pattern = r'^[^A-Z]+$';
        case 'uppercase':
          result.type ??= _SchemaType.string;
          result.pattern = r'^[^a-z]+$';

        // Numeric constraints
        case 'digits':
          result.type ??= _SchemaType.string;
          if (options != null && options.isNotEmpty) {
            final len = int.tryParse(options[0]);
            if (len != null) {
              result.minLength = len;
              result.maxLength = len;
              result.pattern = r'^\d+$';
            }
          }
        case 'digits_between':
          result.type ??= _SchemaType.string;
          result.pattern = r'^\d+$';
          if (options != null && options.length >= 2) {
            result.minLength = int.tryParse(options[0]);
            result.maxLength = int.tryParse(options[1]);
          }
        case 'multiple_of':
          if (options != null && options.isNotEmpty) {
            result.multipleOf = num.tryParse(options[0]);
          }

        // Array constraints
        case 'distinct':
          result.uniqueItems = true;

        // Rules with no direct JSON Schema mapping — ignored
        case 'accepted' ||
            'after' ||
            'after_or_equal' ||
            'before' ||
            'before_or_equal' ||
            'confirmed' ||
            'different' ||
            'same' ||
            'greater_than' ||
            'greater_than_or_equal' ||
            'less_than' ||
            'less_than_or_equal' ||
            'same_size' ||
            'contains' ||
            'in_array' ||
            'required_array_keys' ||
            'date_equals' ||
            'file' ||
            'max_file_size' ||
            'allowed_mime_types' ||
            'file_between' ||
            'file_dimensions' ||
            'file_extensions' ||
            'word' ||
            'starts_with' ||
            'ends_with' ||
            'doesnt_start_with' ||
            'doesnt_end_with' ||
            'not_regex' ||
            'ulid':
          // These rules have no direct JSON Schema equivalent.
          // They are still enforced by the runtime validator.
          break;
      }
    }

    return result;
  }

  /// Builds a `Schema` from parsed rule data.
  static Schema _buildPropertySchema(_ParsedRules rules) {
    switch (rules.type ?? _SchemaType.string) {
      case _SchemaType.string:
        return _buildStringSchema(rules);
      case _SchemaType.integer:
        return _buildIntegerSchema(rules);
      case _SchemaType.number:
        return _buildNumberSchema(rules);
      case _SchemaType.boolean:
        return Schema.boolean();
      case _SchemaType.array:
        return _buildArraySchema(rules);
      case _SchemaType.object:
        return Schema.object();
    }
  }

  static Schema _buildStringSchema(_ParsedRules rules) {
    // For 'min'/'max' on strings, they map to minLength/maxLength
    final effectiveMinLength = rules.minLength ?? rules.min?.toInt();
    final effectiveMaxLength = rules.maxLength ?? rules.max?.toInt();

    return Schema.string(
      minLength: effectiveMinLength,
      maxLength: effectiveMaxLength,
      pattern: rules.pattern,
      format: rules.format,
      enumValues: rules.enumValues,
    );
  }

  static Schema _buildIntegerSchema(_ParsedRules rules) {
    return Schema.integer(
      minimum: rules.min?.toInt(),
      maximum: rules.max?.toInt(),
      multipleOf: rules.multipleOf?.toInt(),
    );
  }

  static Schema _buildNumberSchema(_ParsedRules rules) {
    return Schema.number(
      minimum: rules.min,
      maximum: rules.max,
      multipleOf: rules.multipleOf,
    );
  }

  static Schema _buildArraySchema(_ParsedRules rules) {
    return Schema.list(uniqueItems: rules.uniqueItems == true ? true : null);
  }
}

/// Internal type classification for schema generation.
enum _SchemaType { string, integer, number, boolean, array, object }

/// Accumulates parsed rule data from a pipe-rule string.
class _ParsedRules {
  _SchemaType? type;
  bool isRequired = false;
  bool isNullable = false;
  num? min;
  num? max;
  int? minLength;
  int? maxLength;
  String? format;
  String? pattern;
  List<String>? enumValues;
  num? multipleOf;
  bool? uniqueItems;
}
