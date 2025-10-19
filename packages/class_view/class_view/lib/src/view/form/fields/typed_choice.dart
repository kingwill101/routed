import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/select.dart';
import 'field.dart';

class TypedChoiceField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid_choice":
        "Select a valid choice. %(value)s is not one of the available choices.",
  };

  final List<List<dynamic>> choices;
  final T Function(dynamic) coerce;
  final T emptyValue;

  TypedChoiceField({
    String? name,
    required this.choices,
    required this.coerce,
    required this.emptyValue,
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
    if (value == null || value.toString().isEmpty) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return emptyValue;
    }
    try {
      final coerced = coerce(value);
      if (!isValidValue(coerced)) {
        throw ValidationError({
          'invalid_choice': [
            (errorMessages?["invalid_choice"] ??
                    defaultErrorMessages["invalid_choice"]!)
                .replaceAll("%(value)s", value.toString()),
          ],
        });
      }
      return coerced;
    } catch (e) {
      if (e is ValidationError) rethrow;
      throw ValidationError({
        'invalid_choice': [
          (errorMessages?["invalid_choice"] ??
                  defaultErrorMessages["invalid_choice"]!)
              .replaceAll("%(value)s", value.toString()),
        ],
      });
    }
  }

  bool isValidValue(T value) {
    return choices.any((choice) => _compareValues(choice[0], value));
  }

  bool _compareValues(dynamic a, dynamic b) {
    if (a == null || b == null) return a == b;
    if (a is num && b is num) {
      return (a - b).abs() < 1e-10; // Handle floating point comparison
    }
    return a == b;
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
    return attrs;
  }
}
