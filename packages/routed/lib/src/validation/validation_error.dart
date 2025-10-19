/// Validation error class for form fields
class ValidationError implements Exception {
  /// The error details
  final Map<String, dynamic> details;

  /// Creates a new validation error
  const ValidationError(this.details);

  /// Gets the error message
  String get message => details['message'] as String;

  /// Gets the error code
  String? get code => details['code'] as String?;

  @override
  String toString() => message;
}
