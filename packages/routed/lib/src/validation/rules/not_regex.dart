import 'package:routed/src/validation/rule.dart';

class NotRegexRule extends ValidationRule {
  @override
  String get name => 'not_regex';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field format is invalid.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;
    return !RegExp(options[0]).hasMatch(value.toString());
  }
}
