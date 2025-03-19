import 'package:routed/src/validation/rule.dart';

/// Validation rule that checks if the value is considered "accepted".

class AcceptedRule extends ValidationRule {
  @override
  String get name => 'accepted';
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The field must be accepted.';

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;

    final acceptedValues = ['yes', 'on', 1, '1', true, 'true'];
    return acceptedValues.contains(value);
  }
}
