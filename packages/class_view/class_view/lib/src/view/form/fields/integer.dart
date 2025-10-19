import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/number_input.dart';
import 'field.dart';

class IntegerField extends Field<int> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid": "Enter a whole number.",
    "max_value": "Ensure this value is less than or equal to %(max)d.",
    "min_value": "Ensure this value is greater than or equal to %(min)d.",
    "step_size": "Ensure this value is a multiple of step size %(step)d.",
  };

  final int? maxValue;
  final int? minValue;
  final int? stepSize;

  IntegerField({
    String? name,
    this.maxValue,
    this.minValue,
    this.stepSize,
    Widget? widget,
    Widget? hiddenWidget,
    List<Validator<int>>? validators,
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
         widget: widget ?? NumberInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         validators: [...?validators],
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid": "Enter a whole number.",
             "max_value": "Ensure this value is less than or equal to %(max)d.",
             "min_value":
                 "Ensure this value is greater than or equal to %(min)d.",
             "step_size":
                 "Ensure this value is a multiple of step size %(step)d.",
           },
           ...?errorMessages,
         },
       );

  @override
  int? toDart(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return null;
    }

    final strValue = value.toString().trim();
    int? intValue;

    try {
      // Handle floating point input that represents integers
      final double doubleValue = double.parse(strValue);
      if (doubleValue.truncateToDouble() == doubleValue) {
        intValue = doubleValue.toInt();
      }
    } catch (_) {
      // If double parsing fails, try direct integer parsing
      try {
        intValue = int.parse(strValue);
      } catch (_) {
        // If both parsing attempts fail, throw validation error
        throw ValidationError({
          'invalid': [
            errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
          ],
        });
      }
    }

    if (intValue == null) {
      throw ValidationError({
        'invalid': [
          errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
        ],
      });
    }

    // Validate max value
    if (maxValue != null && intValue > maxValue!) {
      throw ValidationError({
        'max_value': [
          (errorMessages?["max_value"] ?? defaultErrorMessages["max_value"]!)
              .replaceAll("%(max)d", maxValue.toString()),
        ],
      });
    }

    // Validate min value
    if (minValue != null && intValue < minValue!) {
      throw ValidationError({
        'min_value': [
          (errorMessages?["min_value"] ?? defaultErrorMessages["min_value"]!)
              .replaceAll("%(min)d", minValue.toString()),
        ],
      });
    }

    // Validate step size
    if (stepSize != null) {
      final offset = minValue ?? 0;
      final remainder = (intValue - offset) % stepSize!;
      if (remainder != 0) {
        throw ValidationError({
          'step_size': [
            (errorMessages?["step_size"] ?? defaultErrorMessages["step_size"]!)
                .replaceAll("%(step)d", stepSize.toString()),
          ],
        });
      }
    }

    return intValue;
  }

  @override
  Future<void> validate(int? value) async {
    await super.validate(value);

    if (value == null || value.toString().isEmpty) {
      return;
    }

    final intValue = value;
    if (maxValue != null && intValue > maxValue!) {
      throw ValidationError({
        'max_value': [
          (errorMessages?["max_value"] ?? defaultErrorMessages["max_value"]!)
              .replaceAll("%(max)d", maxValue.toString()),
        ],
      });
    }

    if (minValue != null && intValue < minValue!) {
      throw ValidationError({
        'min_value': [
          (errorMessages?["min_value"] ?? defaultErrorMessages["min_value"]!)
              .replaceAll("%(min)d", minValue.toString()),
        ],
      });
    }

    if (stepSize != null) {
      final offset = minValue ?? 0;
      final remainder = (intValue - offset) % stepSize!;
      if (remainder != 0) {
        throw ValidationError({
          'step_size': [
            (errorMessages?["step_size"] ?? defaultErrorMessages["step_size"]!)
                .replaceAll("%(step)d", stepSize.toString()),
          ],
        });
      }
    }
  }

  @override
  Map<String, dynamic> widgetAttrs(Widget widget) {
    final attrs = super.widgetAttrs(widget);
    if (!widget.isHidden) {
      if (maxValue != null) {
        attrs["max"] = maxValue.toString();
      }
      if (minValue != null) {
        attrs["min"] = minValue.toString();
      }
      if (stepSize != null) {
        attrs["step"] = stepSize.toString();
      }
    }
    return attrs;
  }
}
