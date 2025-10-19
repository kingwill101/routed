part of 'context.dart';

/// Represents a generic error in the engine with a message and an optional code.
class EngineError {
  /// The error message.
  final String message;

  /// The optional error code.
  final int? code;

  /// Constructs an [EngineError] with the given [message] and optional [code].
  EngineError({required this.message, this.code});

  /// Returns a string representation of the error.
  ///
  /// If the [code] is `null`, it returns 'EngineError: [message]'.
  /// Otherwise, it returns 'EngineError([code]): [message]'.
  @override
  String toString() {
    if (code == null) return 'EngineError: $message';
    return 'EngineError($code): $message';
  }

  /// Converts this [EngineError] to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'message': message,
    if (code != null) 'code': code,
  };

  /// Creates an [EngineError] from a JSON-compatible map.
  factory EngineError.fromJson(Map<String, dynamic> json) => EngineError(
    message: json['message'] as String,
    code: json['code'] != null ? json['code'] as int? : null,
  );
}

/// Represents a validation error in the engine.
class ValidationError implements EngineError {
  /// A map of validation errors where the key is the field name and the value is a list of error messages.
  Map<String, List<String>> errors;

  /// Constructs a [ValidationError] with an optional [errors] map.
  ///
  /// If no [errors] map is provided, it defaults to an empty map.
  ValidationError([this.errors = const {}]);

  /// The error code for validation errors, which is always 422.
  @override
  int? get code => 422;

  /// The error message for validation errors.
  ///
  /// If there are no errors, it returns 'Validation failed.'.
  /// If there are multiple fields with errors, it returns 'Validation failed. [number of fields] errors.'.
  /// Otherwise, it returns 'Validation failed. [number of errors in the first field] errors.'.
  @override
  String get message {
    if (errors.isEmpty) return 'Validation failed.';

    if (errors.keys.length > 1) {
      return 'Validation failed. ${errors.keys.length} errors.';
    }

    return 'Validation failed. ${errors.values.first.length} errors.';
  }

  /// Returns a string representation of the validation error.
  @override
  String toString() => 'ValidationError: $message';

  /// Converts this [ValidationError] to a JSON-compatible map.
  @override
  Map<String, dynamic> toJson() => {
    'errors': errors,
    'code': code,
    'message': message,
  };

  /// Creates a [ValidationError] from a JSON-compatible map.
  factory ValidationError.fromJson(Map<String, dynamic> json) =>
      ValidationError(
        (json['errors'] as Map).map(
          (key, value) =>
              MapEntry(key as String, (value as List).cast<String>()),
        ),
      );
}

/// Represents a "Not Found" error in the engine.
class NotFoundError extends EngineError {
  NotFoundError({required super.message});

  /// The error code for "Not Found" errors, which is always 404.
  @override
  int? get code => 404;

  /// The error message for "Not Found" errors, which is always 'Not found.'.
  @override
  String get message => 'Not found.';
}

/// Represents an "Unauthorized" error in the engine.
class UnauthorizedError extends EngineError {
  UnauthorizedError({required super.message});

  /// The error code for "Unauthorized" errors, which is always 401.
  @override
  int? get code => 401;

  /// The error message for "Unauthorized" errors, which is always 'Unauthorized.'.
  @override
  String get message => 'Unauthorized.';
}

/// Represents a "Forbidden" error in the engine.
class ForbiddenError extends EngineError {
  ForbiddenError({required super.message});

  /// The error code for "Forbidden" errors, which is always 403.
  @override
  int? get code => 403;

  /// The error message for "Forbidden" errors, which is always 'Forbidden.'.
  @override
  String get message => 'Forbidden.';
}

/// Represents an "Internal Server Error" in the engine.
class InternalServerError extends EngineError {
  InternalServerError({required super.message});

  /// The error code for "Internal Server Error" errors, which is always 500.
  @override
  int? get code => 500;

  /// The error message for "Internal Server Error" errors, which is always 'Internal server error.'.
  @override
  String get message => 'Internal server error.';
}

/// Represents a "Bad Request" error in the engine.
class BadRequestError extends EngineError {
  BadRequestError() : super(message: 'Bad request.');

  /// The error code for "Bad Request" errors, which is always 400.
  @override
  int? get code => 400;
}

/// Represents a "Conflict" error in the engine.
class ConflictError extends EngineError {
  ConflictError({required super.message});

  /// The error code for "Conflict" errors, which is always 409.
  @override
  int? get code => 409;

  /// The error message for "Conflict" errors, which is always 'Conflict.'.
  @override
  String get message => 'Conflict.';
}
