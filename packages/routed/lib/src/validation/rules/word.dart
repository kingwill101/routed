import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a given value is a valid word.
///
/// This class implements the [ValidationRule] interface and provides
/// functionality to validate if a given value is a word consisting of
/// alphanumeric characters and underscores.
class WordRule extends ValidationRule {
  /// The name of the validation rule.
  ///
  /// This is used to identify the rule and can be useful for error
  /// messages or logging.
  @override
  String get name => 'word';

  /// The error message to be displayed when validation fails.
  ///
  /// This message indicates that the field must contain a valid word.
  @override
  String message(dynamic value, [List<String>? options]) =>
      'This field must be a valid word.';

  /// Validates if the given [value] is a valid word.
  ///
  /// This method checks if the [value] is not null and matches the
  /// regular expression for a word, which includes alphanumeric
  /// characters and underscores.
  ///
  /// - [value]: The value to be validated.
  /// - [options]: An optional list of additional options for validation.
  ///
  /// Returns `true` if the [value] is a valid word, otherwise `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return RegExp(r'^\w+$').hasMatch(value.toString());
  }
}
