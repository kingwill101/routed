import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/select_multiple.dart';
import 'field.dart';

class MultipleChoiceField extends Field<List<String>> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid_choice":
        "Select a valid choice. %(value)s is not one of the available choices.",
    "invalid_list": "Enter a list of values.",
  };

  final List<List<dynamic>> choices;

  MultipleChoiceField({
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
    super.showHiddenInitial = false,
    super.localize = false,
    super.disabled = false,
    super.labelSuffix,
    super.templateName,
  }) : super(
         name: name ?? '',
         widget: widget ?? SelectMultiple(choices: choices),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid_choice":
                 "Select a valid choice. %(value)s is not one of the available choices.",
             "invalid_list": "Enter a list of values.",
           },
           ...?errorMessages,
         },
       );

  @override
  List<String>? toDart(dynamic value) {
    if (disabled) {
      return value is List<String> ? value : null;
    }

    // Handle empty values
    if (value == null ||
        value.toString().isEmpty ||
        (value is List && value.isEmpty) ||
        (value is Function)) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return [];
    }

    // Handle non-list values
    if (value is! List) {
      throw ValidationError({
        'invalid_list': [
          errorMessages?["invalid_list"] ??
              defaultErrorMessages["invalid_list"]!,
        ],
      });
    }

    // Convert values and validate
    final result = <String>[];
    for (final val in value) {
      final strVal = val.toString();
      if (!isValidValue(strVal)) {
        throw ValidationError({
          'invalid_choice': [
            (errorMessages?["invalid_choice"] ??
                    defaultErrorMessages["invalid_choice"]!)
                .replaceAll("%(value)s", strVal),
          ],
        });
      }
      result.add(strVal);
    }

    return result;
  }

  bool isValidValue(dynamic value) {
    final textValue = value.toString();

    for (final choice in choices) {
      if (choice[0] != null) {
        if (choice.length > 1 && choice[1] is List) {
          // This is an optgroup, so look inside the group for options
          final groupChoices = choice[1] as List;
          for (final groupChoice in groupChoices) {
            if (groupChoice is List &&
                (value == groupChoice[0] ||
                    textValue == groupChoice[0].toString())) {
              return true;
            }
          }
        } else {
          if (value == choice[0] || textValue == choice[0].toString()) {
            return true;
          }
        }
      }
    }

    return false;
  }

  @override
  Map<String, dynamic> widgetAttrs(Widget widget) {
    final attrs = super.widgetAttrs(widget);
    if (widget is SelectMultiple) {
      attrs["multiple"] = true;
      attrs["choices"] = choices;
    }
    return attrs;
  }

  @override
  bool hasChanged(dynamic initial, dynamic data) {
    if (disabled) {
      return false;
    }

    initial ??= [];
    data ??= [];

    if (initial is! List) {
      initial = [initial];
    }
    if (data is! List) {
      data = [data];
    }

    // Convert all values to strings for comparison
    final initialSet = Set.from(initial.map((v) => v.toString()));
    final dataSet = Set.from(data.map((v) => v.toString()));

    // Compare sets
    if (initialSet.length != dataSet.length) {
      return true;
    }

    // Compare each value after string conversion
    return !initialSet.every((i) => dataSet.contains(i));
  }

  @override
  Future<List<String>?> clean(dynamic value) async {
    final result = toDart(value);
    await validate(result);
    return result;
  }
}
