import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/multi_value_widget.dart';
import 'field.dart';

abstract class MultiValueField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid": "Enter a list of values.",
    "incomplete": "Enter a complete value.",
  };

  final List<Field> fields;
  final bool requireAllFields;

  MultiValueField({
    String? name,
    required this.fields,
    Widget? widget,
    super.hiddenWidget,
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
    this.requireAllFields = true,
  }) : super(
         name: name ?? '',
         widget:
             widget ??
             MultiValueWidget(widgets: fields.map((f) => f.widget).toList()),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "incomplete": "Enter a complete value.",
           },
           ...?errorMessages,
         },
       );

  @override
  T? toDart(dynamic value) {
    if (disabled) {
      return value as T?;
    }

    if (value == null || value.toString().isEmpty) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return null;
    }

    return value as T?;
  }

  @override
  Future<void> validate(dynamic value) async {
    if (value == null || value.toString().isEmpty) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return;
    }

    if (value is! List) {
      throw ValidationError({
        'invalid': [
          errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
        ],
      });
    }

    if (requireAllFields && value.length != fields.length) {
      throw ValidationError({
        'incomplete': [
          errorMessages?["incomplete"] ?? defaultErrorMessages["incomplete"]!,
        ],
      });
    }

    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      final fieldValue = i < value.length ? value[i] : null;

      if (requireAllFields || fieldValue != null) {
        await field.validate(fieldValue);
      }
    }

    final compressed = compress(value);
    if (compressed != null) {
      await super.validate(compressed);
    }
  }

  /// Combines the cleaned values of the different fields into a single value.
  /// Subclasses should implement this method.
  T? compress(List<dynamic> dataList);

  /// Decompresses a single value into a list of values for the individual fields.
  /// First tries to use the field's own decompress logic, then falls back to the widget's
  /// decompress method if available, and finally provides a default implementation.
  List decompress(dynamic value) {
    if (value == null) return [];

    try {
      // Try field-specific decompress logic first
      return decompressValue(value);
    } catch (e) {
      // If field doesn't implement custom decompress, try widget
      if (widget is MultiValueWidget) {
        return (widget as MultiValueWidget).decompress(value);
      }
      // Default fallback
      return [value];
    }
  }

  /// Override this method to provide field-specific decompress logic
  List decompressValue(dynamic value) {
    throw UnimplementedError('Subclasses may implement decompressValue()');
  }

  @override
  Future<T?> clean(dynamic value) async {
    if (value == null || value.toString().isEmpty) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return null;
    }

    if (value is! List) {
      if (disabled) {
        return value as T?;
      }
      throw ValidationError({
        'invalid': [
          errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
        ],
      });
    }

    if (value.length < fields.length && required) {
      throw ValidationError({
        'required': [
          errorMessages?["required"] ?? defaultErrorMessages["required"]!,
        ],
      });
    }

    var cleanData = <dynamic>[];
    var hasErrors = false;
    var errors = <String>[];

    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      final fieldValue = i < value.length ? value[i] : null;

      try {
        final cleanedValue = await field.clean(fieldValue);
        cleanData.add(cleanedValue);
      } catch (e) {
        hasErrors = true;
        errors.add(e.toString());
        cleanData.add(null);
      }
    }

    if (hasErrors) {
      throw ValidationError({
        'invalid': [errors.join(', ')],
      });
    }

    var out = compress(cleanData);
    if (out != null) {
      await validate(cleanData);
    }
    return out;
  }

  @override
  bool hasChanged(dynamic initial, dynamic data) {
    if (disabled) {
      return false;
    }

    if (initial == null && data == null) {
      return false;
    }

    if (initial == null || data == null) {
      return true;
    }

    List initialList;
    if (initial is! List) {
      initialList = decompress(initial);
    } else {
      initialList = initial;
    }

    List dataList;
    if (data is! List) {
      dataList = decompress(data);
    } else {
      dataList = data;
    }

    if (initialList.length != dataList.length) {
      return true;
    }

    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      final initialValue = i < initialList.length ? initialList[i] : null;
      final dataValue = i < dataList.length ? dataList[i] : null;

      if (initialValue == null && dataValue == null) {
        continue;
      }

      if (initialValue == null || dataValue == null) {
        return true;
      }

      if (field.hasChanged(initialValue, dataValue)) {
        return true;
      }
    }

    return false;
  }
}
