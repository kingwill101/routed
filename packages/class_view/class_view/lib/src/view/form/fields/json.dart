import 'dart:convert';

import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/textarea.dart';
import 'field.dart';

/// A field that accepts and validates JSON input.
///
/// This field will validate that the input is valid JSON and convert it to/from
/// Dart objects. The field's clean value will be the parsed JSON data.
class JSONField extends Field<dynamic> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid": "Enter a valid JSON.",
  };

  /// Custom JSON encoder to use for serializing values
  final JsonEncoder? encoder;

  /// Custom JSON decoder to use for deserializing values
  final JsonDecoder? decoder;

  JSONField({
    String? name,
    this.encoder,
    this.decoder,
    Widget? widget,
    Widget? hiddenWidget,
    super.validators,
    super.required = true,
    super.label,
    super.initial,
    super.helpText,
    Map<String, String>? errorMessages,
    super.showHiddenInitial = false,
    super.localize = false,
    super.disabled = false,
    super.labelSuffix,
    super.templateName,
  }) : super(
         name: name ?? '',
         widget: widget ?? Textarea(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid": "Enter a valid JSON.",
           },
           ...?errorMessages,
         },
       );

  @override
  dynamic toDart(dynamic value) {
    if (disabled) {
      return value;
    }

    if (value == null || (value is String && value.trim().isEmpty)) {
      return null;
    }

    // If it's already a non-string value, return it
    if (value is! String) {
      return value;
    }

    final trimmed = value.trim();

    try {
      // Try to decode as JSON
      final decoder = this.decoder ?? const JsonDecoder();
      return decoder.convert(trimmed);
    } catch (_) {
      throw ValidationError({
        'invalid': [
          errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
        ],
      });
    }
  }

  @override
  String prepareValue(dynamic value) {
    if (value == null) {
      return 'null';
    }

    try {
      return (encoder ?? const JsonEncoder()).convert(value);
    } catch (e) {
      // If encoding fails, return the string representation
      return value.toString();
    }
  }

  @override
  bool hasChanged(dynamic initial, dynamic data) {
    if (initial == null && data == null) {
      return false;
    }

    if (initial == null || data == null) {
      return true;
    }

    try {
      // Convert both values to JSON strings for comparison
      final initialJson = prepareValue(initial);
      final dataJson = data is String ? data : prepareValue(data);

      // Parse both as JSON to compare structure rather than string equality
      final jsonDecoder = decoder ?? const JsonDecoder();
      final initialValue = jsonDecoder.convert(initialJson);
      final dataValue = jsonDecoder.convert(dataJson);

      // Compare the parsed values
      return _deepEquals(initialValue, dataValue) == false;
    } catch (e) {
      // If there's any error in conversion, consider them different
      return true;
    }
  }

  @override
  Future<void> validate(dynamic value) async {
    // Check for required field
    if (required &&
        (value == null || (value is String && value.trim().isEmpty))) {
      throw ValidationError({
        'required': [
          errorMessages?["required"] ?? defaultErrorMessages["required"]!,
        ],
      });
    }

    // Skip validation for null/empty values if field is not required
    if (!required &&
        (value == null || (value is String && value.trim().isEmpty))) {
      return;
    }

    // For string values, validate by attempting conversion
    if (value is String) {
      try {
        final decoder = this.decoder ?? const JsonDecoder();
        decoder.convert(value);
      } catch (e) {
        throw ValidationError({
          'invalid': [
            errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
          ],
        });
      }
    }

    await super.validate(value);
  }

  @override
  Future<dynamic> clean(dynamic value) async {
    // If the value is already a cleaned JSON value (not a string), return it
    if (value != null && value is! String) {
      await validate(value);
      return value;
    }

    // Handle null/empty values
    if (value == null || (value is String && value.trim().isEmpty)) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return null;
    }

    // For string values, try to convert to JSON
    if (value is String) {
      final trimmed = value.trim();

      try {
        final decoder = this.decoder ?? const JsonDecoder();
        final result = decoder.convert(trimmed);
        await validate(result);
        return result;
      } catch (_) {
        // If JSON parsing fails, try to validate the string itself
        await validate(trimmed);
        return trimmed;
      }
    }

    return value;
  }
}

/// Helper function to deeply compare two JSON values
bool _deepEquals(dynamic a, dynamic b) {
  if (a == null || b == null) {
    return a == b;
  }

  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }

  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }

  return a == b;
}
