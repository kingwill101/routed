import 'package:routed/src/validation/rule.dart';

class MultipleOfRule extends ValidationRule {
  @override
  String get name => 'multiple_of';

  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field must be a multiple of ${options[0]}.';
    }
    return 'The field must be a multiple of the specified value.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;

    final factor = num.tryParse(options[0]);
    final thisValue = num.tryParse(value.toString());

    if (factor == null || thisValue == null) return false;

    return thisValue % factor == 0;
  }
}
