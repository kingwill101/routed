import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/select.dart';
import 'field.dart';

class ChoiceField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid_choice":
        "Select a valid choice. %(value)s is not one of the available choices.",
  };

  final List<List<dynamic>> choices;

  ChoiceField({
    String? name,
    required this.choices,
    Widget? widget,
    Widget? hiddenWidget,
    super.validators,
    super.required = true,
    super.label,
    super.initial,
    super.helpText,
    Map<String, String>? errorMessages,
    super.showHiddenInitial,
    super.localize,
    super.disabled = false,
    super.labelSuffix,
    super.templateName,
  }) : super(
         name: name ?? '',
         widget: widget ?? Select(choices: choices),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid_choice":
                 "Select a valid choice. %(value)s is not one of the available choices.",
           },
           ...?errorMessages,
         },
       );

  @override
  T? toDart(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return required ? null : '' as T;
    }

    // Convert numeric values to string if needed
    if (value is num) {
      value = value.toString();
    }

    return value as T;
  }

  @override
  Future<void> validate(T? value) async {
    await super.validate(value);

    if (value == null || (value is String && value.trim().isEmpty)) {
      if (required) {
        final message =
            errorMessages?["required"] ?? defaultErrorMessages["required"]!;
        throw ValidationError({
          'required': [message],
        }, message);
      }
      return;
    }

    if (!isValidValue(value)) {
      final message =
          (errorMessages?["invalid_choice"] ??
                  defaultErrorMessages["invalid_choice"]!)
              .replaceAll("%(value)s", value.toString());
      throw ValidationError({
        'invalid_choice': [message],
      }, message);
    }
  }

  bool isValidValue(dynamic value) {
    String strValue = value.toString();

    for (var choice in choices) {
      if (choice[0].toString() == strValue) {
        return true;
      }

      // Check if this is a group
      if (choice.length == 2 && choice[1] is List) {
        var subChoices = choice[1] as List;
        for (var subChoice in subChoices) {
          if (subChoice is List && subChoice[0].toString() == strValue) {
            return true;
          }
        }
      }
    }

    return false;
  }

  List<List<dynamic>> get validChoices {
    return choices.where((choice) => choice[0] != null).toList();
  }

  @override
  Map<String, dynamic> widgetAttrs(Widget widget) {
    final attrs = super.widgetAttrs(widget);
    if (widget is Select) {
      attrs["choices"] = validChoices.toString();
    }
    if (disabled) {
      attrs["disabled"] = "disabled";
    }
    return attrs;
  }
}
