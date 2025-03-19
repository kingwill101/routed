import 'package:routed/src/validation/rule.dart';

/// A validation rule that checks if a given value is a valid slug.
///
/// A slug is a URL-friendly string typically used in web development.
/// It usually contains only lowercase letters, numbers, and hyphens.
class SlugRule extends ValidationRule {
  /// The name of the validation rule.
  @override
  String get name => 'slug';

  /// The error message returned when the validation fails.
  @override
  String message(dynamic value, [List<String>? options]) =>
      'This field must be a valid slug.';

  /// Validates whether the given [value] is a valid slug.
  ///
  /// A valid slug contains only lowercase letters, numbers, and hyphens.
  ///
  /// [value] - The value to be validated. It can be of any type.
  /// [options] - An optional list of additional options for validation.
  ///
  /// Returns `true` if the [value] is a valid slug, otherwise `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null) return false;
    return RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value.toString());
  }
}
