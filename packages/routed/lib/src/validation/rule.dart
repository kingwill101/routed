abstract class ValidationRule {
  /// The name of the validation rule.
  /// This should be a unique identifier for the rule.
  ///
  /// This property is intended to provide a unique name for each validation rule.
  /// It can be used to differentiate between different rules and to reference
  /// specific rules when needed. The name should be descriptive enough to convey
  /// the purpose of the rule but concise enough to be easily used in code.
  String get name;

  /// The message that will be displayed if the validation fails.
  /// This message should be user-friendly and explain why the validation failed.
  ///
  /// This property provides feedback to the user when a validation rule is not met.
  /// The message should be clear and informative, helping the user understand what
  /// went wrong and how they can correct the input. It is important that the message
  /// is written in a way that is easy to understand, avoiding technical jargon.
  String get message;

  /// Validates the given value against the rule.
  ///
  /// This method checks whether the provided value meets the criteria defined by the
  /// validation rule. It can be used to enforce data integrity and ensure that inputs
  /// conform to expected formats or constraints.
  ///
  /// [value] - The value to be validated. This can be of any type, allowing for flexible
  /// validation logic that can handle various data types such as strings, numbers, or
  /// custom objects.
  ///
  /// [options] - An optional list of strings that can provide additional context or parameters
  /// for the validation. These options can be used to customize the validation logic, for example,
  /// by specifying minimum or maximum lengths, allowed characters, or other constraints.
  ///
  /// Returns `true` if the value passes the validation, otherwise `false`. If the validation fails,
  /// the `message` property should be used to provide feedback to the user.
  bool validate(dynamic value, [List<String>? options]);
}
