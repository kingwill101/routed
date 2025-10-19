import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/text_input.dart';
import 'field.dart';

class UUIDField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid": "Enter a valid UUID.",
  };

  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  UUIDField({
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
         widget: widget ?? TextInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid": "Enter a valid UUID.",
           },
           ...?errorMessages,
         },
       );

  @override
  T? toDart(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return null;
    }
    final uuid = value.toString().toLowerCase();
    if (!_uuidRegex.hasMatch(uuid)) {
      throw ValidationError({
        'invalid': [
          errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
        ],
      });
    }
    return uuid as T;
  }
}
