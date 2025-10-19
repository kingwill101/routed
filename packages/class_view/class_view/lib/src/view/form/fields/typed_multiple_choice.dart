import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/select.dart';
import 'field.dart';

class TypedMultipleChoiceField<T> extends Field<List<T>?> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid_choice":
        "Select a valid choice. %(value)s is not one of the available choices.",
  };

  final List<List<dynamic>> choices;
  final T Function(dynamic) coerce;
  final List<T>? emptyValue;

  TypedMultipleChoiceField({
    String? name,
    required this.choices,
    required this.coerce,
    this.emptyValue = const [],
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
         widget: widget ?? Select(choices: choices, multiple: true),
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
  List<T>? toDart(dynamic value) {
    if (value == null ||
        (value is List && value.isEmpty) ||
        value.toString().isEmpty) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return emptyValue;
    }

    List<dynamic> valueList;
    if (value is List) {
      valueList = value;
    } else {
      valueList = [value];
    }

    final result = <T>[];
    for (var item in valueList) {
      try {
        final coerced = coerce(item);
        if (!isValidValue(coerced)) {
          throw ValidationError({
            'invalid_choice': [
              (errorMessages?["invalid_choice"] ??
                      defaultErrorMessages["invalid_choice"]!)
                  .replaceAll("%(value)s", item.toString()),
            ],
          });
        }
        result.add(coerced);
      } catch (e) {
        if (e is ValidationError) rethrow;
        throw ValidationError({
          'invalid_choice': [
            (errorMessages?["invalid_choice"] ??
                    defaultErrorMessages["invalid_choice"]!)
                .replaceAll("%(value)s", item.toString()),
          ],
        });
      }
    }
    return result;
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
      attrs["multiple"] = true;
    }
    return attrs;
  }
}
