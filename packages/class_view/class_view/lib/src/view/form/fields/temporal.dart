import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/text_input.dart';
import 'field.dart';

abstract class BaseTemporalField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid": "Enter a valid value.",
  };

  final List<String> inputFormats;

  BaseTemporalField({
    String? name,
    this.inputFormats = const [],
    Widget? widget,
    Widget? hiddenWidget,
    super.validators,
    super.required,
    super.label,
    super.initial,
    super.helpText,
    super.errorMessages,
    super.showHiddenInitial,
    super.localize,
    super.disabled,
    super.labelSuffix,
    super.templateName,
  }) : super(
         name: name ?? '',
         widget: widget ?? TextInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
       );

  @override
  T? toDart(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return null;
    }

    if (value is T) {
      return value;
    }

    final stringValue = value.toString().trim();
    for (final format in inputFormats) {
      try {
        return strptime(stringValue, format);
      } catch (e) {
        continue;
      }
    }

    throw ValidationError({
      'invalid': [
        errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
      ],
    });
  }

  T strptime(String value, String format);
}
