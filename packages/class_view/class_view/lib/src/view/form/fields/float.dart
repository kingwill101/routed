import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/number_input.dart';
import 'field.dart';

/// A field for handling floating point numbers.
class FloatField extends Field<double> {
  /// The maximum allowed value for this field.
  final double? maxValue;

  /// The minimum allowed value for this field.
  final double? minValue;

  /// The step size for this field.
  final double? stepSize;

  /// Creates a new float field.
  FloatField({
    this.maxValue,
    this.minValue,
    this.stepSize,
    super.required = true,
    Widget? widget,
    super.label,
    super.initial,
    super.helpText,
    super.errorMessages,
    super.showHiddenInitial = false,
    super.validators = const [],
    super.localize = false,
    super.disabled = false,
    super.labelSuffix,
  }) : super(
         widget:
             widget ??
             NumberInput(
               attrs: {
                 if (maxValue != null) 'max': maxValue.toString(),
                 if (minValue != null) 'min': minValue.toString(),
                 if (stepSize != null) 'step': stepSize.toString(),
               },
             ),
       );

  @override
  double? toDart(dynamic value) {
    if (value == null || value == '') {
      if (required) {
        throw ValidationError({
          'required': ['This field is required.'],
        });
      }
      return null;
    }

    double? floatValue;
    try {
      if (value is num) {
        floatValue = value.toDouble();
      } else {
        final trimmed = value.toString().trim();
        floatValue = double.parse(trimmed);
      }
    } catch (e) {
      throw ValidationError({
        'invalid': ['Enter a number.'],
      });
    }

    if (floatValue.isInfinite || floatValue.isNaN) {
      throw ValidationError({
        'invalid': ['Enter a number.'],
      });
    }

    if (maxValue != null && floatValue > maxValue!) {
      throw ValidationError({
        'max_value': ['Ensure this value is less than or equal to $maxValue.'],
      });
    }

    if (minValue != null && floatValue < minValue!) {
      throw ValidationError({
        'min_value': [
          'Ensure this value is greater than or equal to $minValue.',
        ],
      });
    }

    if (stepSize != null) {
      final offset = minValue ?? 0.0;
      final steps = (floatValue - offset) / stepSize!;
      final roundedSteps = steps.round();

      // Allow for floating point imprecision
      if ((steps - roundedSteps).abs() > 1e-10) {
        if (minValue != null) {
          throw ValidationError({
            'invalid': [
              'Ensure this value is a multiple of step size $stepSize, starting from $minValue, '
                  'e.g. $minValue, ${minValue! + stepSize!}, ${minValue! + (stepSize! * 2)}, and so on.',
            ],
          });
        }
        throw ValidationError({
          'invalid': [
            'Ensure this value is a multiple of step size $stepSize.',
          ],
        });
      }
    }

    return floatValue;
  }

  @override
  bool hasChanged(dynamic initial, dynamic data) {
    // Convert to typed values first
    double? dartInitial;
    double? dartData;

    try {
      dartInitial = toDart(initial);
    } catch (_) {
      dartInitial = null;
    }

    try {
      dartData = toDart(data);
    } catch (_) {
      dartData = null;
    }

    // Handle the case where both values represent the same number
    // but might have different string representations
    if (dartInitial != null && dartData != null) {
      return (dartInitial - dartData).abs() >
          1e-10; // Using small epsilon for float comparison
    }
    return dartInitial != dartData;
  }
}
