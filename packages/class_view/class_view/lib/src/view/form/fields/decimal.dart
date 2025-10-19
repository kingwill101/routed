import 'package:decimal/decimal.dart';

import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/number_input.dart';
import 'field.dart';

class DecimalField extends Field<Decimal> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid": "Enter a decimal number.",
    "max_value": "Ensure this value is less than or equal to %(limit_value)s.",
    "min_value":
        "Ensure this value is greater than or equal to %(limit_value)s.",
    "max_decimal_places":
        "Ensure that there are no more than %(max)s decimal places.",
    "max_digits": "Ensure that there are no more than %(max)s digits in total.",
    "max_whole_digits":
        "Ensure that there are no more than %(max)s digits before the decimal point.",
  };

  final Decimal? maxValue;
  final Decimal? minValue;
  final int? maxDecimalPlaces;
  final int? maxDigits;

  DecimalField({
    String? name,
    this.maxValue,
    this.minValue,
    this.maxDecimalPlaces,
    this.maxDigits,
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
    super.disabled,
    super.labelSuffix,
    super.templateName,
  }) : super(
         name: name ?? '',
         widget: widget ?? NumberInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid": "Enter a decimal number.",
             "max_value":
                 "Ensure this value is less than or equal to %(limit_value)s.",
             "min_value":
                 "Ensure this value is greater than or equal to %(limit_value)s.",
             "max_decimal_places":
                 "Ensure that there are no more than %(max)s decimal places.",
             "max_digits":
                 "Ensure that there are no more than %(max)s digits in total.",
             "max_whole_digits":
                 "Ensure that there are no more than %(max)s digits before the decimal point.",
           },
           ...?errorMessages,
         },
       );

  @override
  Decimal? toDart(dynamic value) {
    if (value == null || (value is String && value.trim().isEmpty)) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?['required'] ?? defaultErrorMessages['required']!,
          ],
        });
      }
      return null;
    }

    String strValue;
    if (value is Decimal) {
      strValue = value.toString();
    } else {
      strValue = value.toString().trim();
    }

    try {
      final decimal = Decimal.parse(strValue);

      // Get string representation without scientific notation
      final String normalizedStr = decimal.toString();

      // Split into whole and decimal parts
      final parts = normalizedStr.split('.');
      final String wholeStr = parts[0].replaceAll(RegExp(r'^-?0+'), '');
      final String decimalStr = parts.length > 1 ? parts[1] : '';

      // Count significant digits
      final wholeDigits = wholeStr.isEmpty || wholeStr == '-'
          ? 0
          : wholeStr.replaceAll('-', '').length;
      final decimalDigits = decimalStr.length;
      final totalDigits = wholeDigits + decimalDigits;

      // Validate max_digits
      if (maxDigits != null && totalDigits > maxDigits!) {
        throw ValidationError({
          'max_digits': [
            (errorMessages?["max_digits"] ??
                    defaultErrorMessages["max_digits"]!)
                .replaceAll("%(max)s", maxDigits.toString()),
          ],
        });
      }

      // Validate max_decimal_places
      if (maxDecimalPlaces != null && decimalDigits > maxDecimalPlaces!) {
        throw ValidationError({
          'max_decimal_places': [
            (errorMessages?["max_decimal_places"] ??
                    defaultErrorMessages["max_decimal_places"]!)
                .replaceAll("%(max)s", maxDecimalPlaces.toString()),
          ],
        });
      }
      // If both max_digits and max_decimal_places are specified, validate max whole digits
      if (maxDigits != null && maxDecimalPlaces != null && decimalDigits > 0) {
        final maxWholeDigits = maxDigits! - maxDecimalPlaces!;
        if (wholeDigits > maxWholeDigits) {
          throw ValidationError({
            'max_whole_digits': [
              (errorMessages?["max_whole_digits"] ??
                      defaultErrorMessages["max_whole_digits"]!)
                  .replaceAll("%(max)s", maxWholeDigits.toString()),
            ],
          });
        }
      }

      return decimal;
    } catch (e) {
      if (e is ValidationError) {
        rethrow;
      }
      throw ValidationError({
        'invalid': ['"$strValue" value must be a decimal number.'],
      });
    }
  }

  @override
  Future<void> validate(Decimal? value) async {
    await super.validate(value);

    if (value == null) {
      return;
    }

    if (maxValue != null && value > maxValue!) {
      throw ValidationError({
        'max_value': [
          (errorMessages?["max_value"] ?? defaultErrorMessages["max_value"]!)
              .replaceAll("%(limit_value)s", maxValue.toString()),
        ],
      });
    }

    if (minValue != null && value < minValue!) {
      throw ValidationError({
        'min_value': [
          (errorMessages?["min_value"] ?? defaultErrorMessages["min_value"]!)
              .replaceAll("%(limit_value)s", minValue.toString()),
        ],
      });
    }
  }

  @override
  Map<String, dynamic> widgetAttrs(Widget widget) {
    final attrs = super.widgetAttrs(widget);
    if (widget is NumberInput) {
      if (maxDecimalPlaces != null) {
        attrs["step"] = "0.${List.filled(maxDecimalPlaces! - 1, '0').join()}1";
      }
      if (minValue != null) {
        attrs["min"] = minValue.toString();
      }
      if (maxValue != null) {
        attrs["max"] = maxValue.toString();
      }
    }
    return attrs;
  }
}
