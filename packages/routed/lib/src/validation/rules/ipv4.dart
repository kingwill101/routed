import 'package:routed/src/validation/rule.dart';

/// Validation rule that checks if the value is a valid IPv4 address.
class Ipv4Rule extends ValidationRule {
  @override
  String get name => 'ipv4';

  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be a valid IPv4 address.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;

    return RegExp(
      r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
    ).hasMatch(value.toString());
  }
}
