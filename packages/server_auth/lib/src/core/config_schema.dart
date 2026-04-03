import 'package:json_schema_builder/json_schema_builder.dart';

extension _SchemaDefaults on Schema {
  Schema withDefault(Object? defaultValue) {
    return Schema.fromMap({...value, 'default': defaultValue});
  }
}

/// Lightweight schema builders used by auth provider registration.
class ConfigSchema {
  static Schema object({
    String? title,
    String? description,
    Map<String, Schema>? properties,
    List<String>? required,
    Object? additionalProperties,
    Map<String, dynamic>? defaultValue,
  }) {
    final map = <String, dynamic>{
      'type': 'object',
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (properties != null)
        'properties': properties.map(
          (key, value) => MapEntry(key, value.value),
        ),
      if (required != null) 'required': required,
      'additionalProperties': additionalProperties ?? false,
    };
    var schema = Schema.fromMap(map);
    if (defaultValue != null) {
      schema = schema.withDefault(defaultValue);
    }
    return schema;
  }

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
}
