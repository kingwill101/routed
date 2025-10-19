import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/checkbox_input.dart';
import '../widgets/hidden_input.dart';
import 'field.dart';

class BooleanField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
  };

  BooleanField({
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
         widget: widget ?? CheckboxInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {"required": "This field is required."},
           ...?errorMessages,
         },
       );

  @override
  T? toDart(dynamic value) {
    if (value is String && (value.toLowerCase() == "false" || value == "0")) {
      return false as T?;
    }
    return (value != null && value != false) as T?;
  }

  @override
  Future<void> validate(T? value) async {
    if (required && (value == null || value == false)) {
      throw ValidationError({
        'required': [
          errorMessages?["required"] ?? defaultErrorMessages["required"]!,
        ],
      });
    }
  }

  @override
  bool hasChanged(dynamic initial, dynamic data) {
    if (disabled) return false;
    return toDart(initial) != toDart(data);
  }
}
