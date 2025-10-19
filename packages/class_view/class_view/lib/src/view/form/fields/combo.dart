import '../validation.dart';
import '../widgets/text_input.dart';
import 'field.dart';

/// A Field whose clean() method calls multiple Field clean() methods.
///
/// This field is useful when you want to apply different validation rules in sequence.
class ComboField extends Field<String> {
  final List<Field<dynamic>> fields;

  ComboField({
    required this.fields,
    String? name,
    super.required = true,
    super.label,
    super.initial,
    super.helpText,
    Map<String, String>? errorMessages,
    super.showHiddenInitial = false,
    super.disabled = false,
    super.labelSuffix,
    super.localize = true,
    super.templateName,
  }) : super(
         name: name ?? '',
         widget: TextInput(),
         errorMessages: {
           ...const {"required": "This field is required."},
           ...?errorMessages,
         },
       );

  @override
  String? toDart(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return required ? null : '';
    }
    return value.toString();
  }

  @override
  Future<void> validate(String? value) async {
    await super.validate(value);

    if (value == null || value.isEmpty) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return;
    }

    // Run the value through each field's validation
    dynamic cleanedValue = value;
    for (var field in fields) {
      cleanedValue = await field.clean(cleanedValue);
    }
  }
}
