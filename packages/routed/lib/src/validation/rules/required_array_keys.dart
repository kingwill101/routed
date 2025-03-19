import 'package:routed/src/validation/rule.dart';

class RequiredArrayKeysRule extends ValidationRule {
  @override
  String get name => 'required_array_keys';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The array must contain the following keys: ${options?.join(', ')}.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty || value is! Map) {
      return false;
    }

    final mapValue = value;
    for (final key in options) {
      if (!mapValue.containsKey(key)) return false;
    }
    return true;
  }
}
