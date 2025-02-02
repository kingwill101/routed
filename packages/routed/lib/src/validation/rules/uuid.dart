import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a given value is a valid UUID (Universally Unique Identifier).
class UuidRule implements ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'uuid';

  /// The error message to be displayed if the validation fails.
  @override
  String get message => 'This field must be a valid UUID.';

  /// Validates whether the provided [value] is a valid UUID.
  ///
  /// A UUID is a 128-bit number used to uniquely identify information in computer systems.
  /// This method uses a regular expression to check if the [value] matches the standard UUID format.
  ///
  /// The [value] parameter is the value to be validated. It can be of any type.
  /// The [options] parameter is an optional list of strings that can be used to provide additional options for validation.
  ///
  /// Returns `true` if the [value] is a valid UUID, otherwise returns `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(value.toString());
  }
}
