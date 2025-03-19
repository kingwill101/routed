import 'package:routed/src/validation/rule.dart';
import 'package:routed/src/binding/multipart.dart';

/// A validation rule that checks if the given value is a file.
///
/// This rule is used to ensure that the value being validated is an instance
/// of [MultipartFile]. If the value is not a file, the validation will fail.
class FileRule extends ValidationRule {
  /// The name of the validation rule.
  ///
  /// This is used to identify the rule in validation configurations.
  @override
  String get name => 'file';

  /// The error message to be displayed if validation fails.
  ///
  /// This message indicates that the field must be a file.
  @override
  String message(dynamic value, [List<String>? options]) =>
      'This field must be a file.';

  /// Validates whether the given value is a file.
  ///
  /// This method checks if the [value] is an instance of [MultipartFile].
  ///
  /// [value] - The value to be validated.
  /// [options] - Additional options for validation (not used in this rule).
  ///
  /// Returns `true` if the value is a file, otherwise `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    return value is MultipartFile;
  }
}

/// A validation rule that checks if the file size does not exceed a specified limit.
///
/// This rule is used to ensure that the size of the file being validated does not
/// exceed the maximum allowed size specified in the options.
class MaxFileSizeRule extends ValidationRule {
  /// The name of the validation rule.
  ///
  /// This is used to identify the rule in validation configurations.
  @override
  String get name => 'max_file_size';

  /// The error message to be displayed if validation fails.
  ///
  /// This message indicates that the file size must not exceed the specified limit.
  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The file size must not exceed ${options[0]} bytes.';
    }
    return 'The file size must not exceed the limit.';
  }

  /// Validates whether the file size does not exceed the specified limit.
  ///
  /// This method checks if the [value] is an instance of [MultipartFile] and if
  /// the file size is less than or equal to the maximum size specified in the [options].
  ///
  /// [value] - The value to be validated.
  /// [options] - A list containing the maximum file size as a string.
  ///
  /// Returns `true` if the file size does not exceed the limit, otherwise `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value is! MultipartFile || options == null || options.isEmpty) {
      return false;
    }
    final maxSize = int.tryParse(options[0]);
    if (maxSize == null) return false;
    return value.size <= maxSize;
  }
}

/// A validation rule that checks if the file's MIME type is allowed.
///
/// This rule is used to ensure that the MIME type of the file being validated
/// is one of the allowed types specified in the options.
class AllowedMimeTypesRule extends ValidationRule {
  /// The name of the validation rule.
  ///
  /// This is used to identify the rule in validation configurations.
  @override
  String get name => 'allowed_mime_types';

  /// The error message to be displayed if validation fails.
  ///
  /// This message indicates that the file type is not allowed.
  @override
  String message(dynamic value, [List<String>? options]) =>
      'The file type is not allowed.';

  /// Validates whether the file's MIME type is allowed.
  ///
  /// This method checks if the [value] is an instance of [MultipartFile] and if
  /// the MIME type of the file is one of the allowed types specified in the [options].
  ///
  /// [value] - The value to be validated.
  /// [options] - A list containing the allowed MIME types as strings.
  ///
  /// Returns `true` if the MIME type is allowed, otherwise `false`.
  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value is! MultipartFile || options == null || options.isEmpty) {
      return false;
    }
    final allowedTypes = options;
    return allowedTypes.contains(value.contentType);
  }
}
