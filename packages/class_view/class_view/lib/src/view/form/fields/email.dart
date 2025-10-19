import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/email_input.dart';
import '../widgets/hidden_input.dart';
import 'field.dart';

class EmailField extends Field<String> {
  static const _defaultErrorMessages = {
    "required": "This field is required.",
    "invalid": "Enter a valid email address.",
  };

  @override
  Map<String, String> get defaultErrorMessages => _defaultErrorMessages;

  EmailField({
    String? name,
    Widget? widget,
    Widget? hiddenWidget,
    List<Validator<String>> validators = const [],
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
    int? maxLength,
  }) : super(
         name: name ?? '',
         widget: widget ?? EmailInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         validators: [
           EmailValidator(
             customErrorMessage:
                 errorMessages?["invalid"] ?? _defaultErrorMessages["invalid"],
           ),
           if (maxLength != null) MaxLengthValidator(maxLength),
           ...validators,
         ],
         errorMessages: {..._defaultErrorMessages, ...?errorMessages},
       );

  @override
  String? toDart(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return null;
    }
    final email = value.toString().trim().toLowerCase();
    return email.isNotEmpty ? email : null;
  }
}
