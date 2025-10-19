import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/null_boolean_select.dart';
import 'field.dart';

class NullBooleanField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid": "Enter a valid value.",
  };

  NullBooleanField({
    String? name,
    Widget? widget,
    Widget? hiddenWidget,
    super.validators,
    super.required,
    super.label,
    super.initial,
    super.helpText,
    Map<String, String>? errorMessages,
    super.showHiddenInitial,
    super.localize,
    super.disabled,
    super.labelSuffix,
    super.templateName,
  }) : super(
         name: name ?? '',
         widget: widget ?? NullBooleanSelect(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid": "Enter a valid value.",
           },
           ...?errorMessages,
         },
       );

  @override
  T? toDart(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return null;
    }

    final stringValue = value.toString().toLowerCase();
    if (stringValue == '1' || stringValue == 'true') {
      return true as T;
    } else if (stringValue == '0' || stringValue == 'false') {
      return false as T;
    }
    return null;
  }

  @override
  bool hasChanged(dynamic initial, dynamic data) {
    if (disabled) return false;

    // Convert both values using toDart to normalize them
    final initialValue = toDart(initial);
    final dataValue = toDart(data);

    // Handle null cases first
    if (initialValue == null && dataValue == null) return false;
    if (initialValue == null || dataValue == null) return true;

    // Compare non-null values
    return initialValue != dataValue;
  }

  @override
  Future<void> validate(T? value) async {
    // No validation required for NullBooleanField.
  }
}
