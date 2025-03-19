import 'package:routed/src/validation/abstract_rule.dart';

class DecimalRule extends AbstractValidationRule {
  @override
  String get name => 'decimal';
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      final min = int.tryParse(options[0]) ?? 0;
      final max = options.length > 1 ? int.tryParse(options[1]) : null;

      if (max != null) {
        return 'The field must have between $min and $max decimal places.';
      }
      return 'The field must have exactly $min decimal places.';
    }
    return 'The field must have a valid number of decimal places.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;

    final valueString = value.toString();
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(valueString)) {
      return false; // Not a number
    }

    if (options != null && options.isNotEmpty) {
      final min = int.tryParse(options[0]) ?? 0;
      final max = options.length > 1 ? int.tryParse(options[1]) : null;

      final decimalPart = valueString.contains('.')
          ? valueString.split('.').last.length
          : 0; // Count decimal places

      if (max != null) {
        return decimalPart >= min && decimalPart <= max;
      } else {
        return decimalPart == min;
      }
    }

    return true; // Valid decimal if no options provided.
  }
}
