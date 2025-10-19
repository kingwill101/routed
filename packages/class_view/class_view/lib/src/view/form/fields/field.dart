import 'package:meta/meta.dart';

import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart' show HiddenInput;
import '../widgets/text_input.dart';

/// Base class for all form fields.
///
/// A field is responsible for managing data, validation, and rendering
/// using a widget. This class provides the basic attributes and methods
/// required for handling form fields. Subclasses can override methods
/// to customize behavior.
abstract class Field<T> {
  /// Default error messages for this field type
  @protected
  final Map<String, String> defaultErrorMessages = const {
    'required': 'This field is required.',
    'invalid': 'Enter a valid value.',
  };

  /// Default validators for this field type
  @protected
  final List<Validator<T>> defaultValidators = const [];

  /// Default widget to use when rendering this type of Field.
  Widget widget;

  /// Default widget to use when rendering this as "hidden".
  Widget hiddenWidget;

  /// Whether the field is required.
  bool required;

  /// The label for the field.
  final String? label;

  /// The initial value for the field.
  final T? initial;

  /// Help text for the field.
  final String? helpText;

  /// Custom error messages.
  final Map<String, String>? errorMessages;

  /// Whether to show a hidden initial value.
  final bool showHiddenInitial;

  /// Additional validators.
  final List<Validator<T>> validators;

  /// Whether the field should be localized.
  final bool localize;

  /// Whether the field is disabled.
  bool disabled;

  /// Suffix to be added to the label.
  final String? labelSuffix;

  /// Template name for rendering.
  final String? templateName;

  /// The name of the field
  final String name;

  Field({
    Widget? widget,
    Widget? hiddenWidget,
    this.required = true,
    this.label,
    this.initial,
    this.helpText,
    this.errorMessages,
    this.showHiddenInitial = false,
    this.validators = const [],
    this.localize = false,
    this.disabled = false,
    this.labelSuffix,
    this.templateName,
    String? name,
  }) : widget = widget ?? TextInput(),
       hiddenWidget = hiddenWidget ?? HiddenInput(),
       name = name ?? '' {
    // Let the widget know whether it should display as required.
    this.widget.isRequired = required;

    // Hook into widgetAttrs for any Field-specific HTML attributes.
    final extraAttrs = widgetAttrs(this.widget);
    if (extraAttrs.isNotEmpty) {
      this.widget.attrs.addAll(extraAttrs);
    }

    // Set localization on widget if needed
    if (localize) {
      this.widget.isLocalized = true;
    }
  }

  /// Prepare the value for rendering.
  T? prepareValue(T? value) => value;

  /// Convert the value to the appropriate type.
  T? toDart(dynamic value) {
    if (value == null) return null;
    // Let subclasses handle type conversion
    return value as T?;
  }

  /// Validate the field value.
  Future<void> validate(T? value) async {
    if (required && (value == null || value.toString().isEmpty)) {
      final message =
          errorMessages?["required"] ?? defaultErrorMessages["required"]!;
      throw ValidationError({
        'required': [message],
      }, message);
    }

    // Run all validators in sequence
    final allValidators = [...defaultValidators, ...validators];
    for (final validator in allValidators) {
      await validator.validate(value);
    }
  }

  /// Clean the field value.
  Future<T?> clean(dynamic value) async {
    final dartValue = toDart(value);
    await validate(dartValue);
    return dartValue;
  }

  /// Return the value to be shown for this field on render.
  T? boundData(dynamic data, T? initial) {
    if (disabled) {
      return initial;
    }
    try {
      return toDart(data);
    } catch (e) {
      // If conversion fails, return null or the raw data
      return data as T?;
    }
  }

  /// Return any HTML attributes that should be added to the widget.
  Map<String, dynamic> widgetAttrs(Widget widget) => {};

  /// Check if the field value has changed.
  bool hasChanged(dynamic initial, dynamic data) {
    if (disabled) return false;

    // Handle null cases first
    if (initial == null && data == null) return false;
    if (initial == null || data == null) return true;

    // Compare non-null values - try to convert to dart types for proper comparison
    // but fall back to string comparison if conversion fails
    try {
      final dartInitial = toDart(initial);
      final dartData = toDart(data);

      if (dartInitial == null && dartData == null) return false;
      if (dartInitial == null || dartData == null) return true;

      return dartInitial.toString() != dartData.toString();
    } catch (e) {
      // If type conversion fails, fall back to string comparison
      return initial.toString() != data.toString();
    }
  }

  /// Return a BoundField instance for accessing the form field in a template.
  dynamic getBoundField(dynamic form, String fieldName) {
    // Fixed undefined class 'BoundField' and 'Form' by making them dynamic.
    return null; // Placeholder implementation.
  }

  /// Deep copy the field instance.
  Field<T> deepCopy() {
    // Fixed undefined 'deepCopy' method for Widget by removing its usage.
    throw UnimplementedError(
      "Deep copy is not implemented for abstract Field.",
    );
  }

  /// Run all validators on the given value
  Future<void> runValidators(T? value) async {
    if (value == null || value.toString().isEmpty) {
      return;
    }
    final errors = <String>[];
    for (final validator in validators) {
      try {
        await validator.validate(value);
      } catch (e) {
        if (e is ValidationError) {
          errors.add(e.message);
        }
      }
    }
    if (errors.isNotEmpty) {
      throw ValidationError({'invalid': errors});
    }
  }
}
