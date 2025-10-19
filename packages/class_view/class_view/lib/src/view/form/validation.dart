import 'package:acanthis/acanthis.dart' as acanthis;

class Validator<T> {
  const Validator();

  /// Validates the given value.
  ///
  /// Throws a [ValidationError] if the value is invalid.
  Future<void> validate(T? value) async {
    // Override this method in subclasses to implement custom validation logic.
  }
}

/// Exception thrown when form validation fails
class ValidationError implements Exception {
  final Map<String, List<String>> errors;
  final String message;
  final String code;

  ValidationError(
    this.errors, [
    this.message = 'Validation failed',
    this.code = 'validation_failed',
  ]);

  String get errorMessages =>
      errors.entries.map((e) => '${e.key}: ${e.value.join(', ')}').join(', ');

  @override
  String toString() => 'Validation failed: $errorMessages';
}

class MinLengthValidator<T> extends Validator<T> {
  final int minLength;

  MinLengthValidator(this.minLength);

  @override
  Future<void> validate(T? value) async {
    if (value != null && value.toString().length < minLength) {
      throw ValidationError({
        'min_length': ["Ensure this value has at least $minLength characters."],
      });
    }
  }
}

class MaxLengthValidator<T> extends Validator<T> {
  final int maxLength;

  MaxLengthValidator(this.maxLength);

  @override
  Future<void> validate(T? value) async {
    if (value != null && value.toString().length > maxLength) {
      throw ValidationError({
        'max_length': ["Ensure this value has at most $maxLength characters."],
      });
    }
  }
}

class ProhibitNullCharactersValidator<T> extends Validator<T> {
  @override
  Future<void> validate(T? value) async {
    if (value != null && value.toString().contains('\u0000')) {
      throw ValidationError({
        'prohibit_null_characters': ["Null characters are not allowed."],
      });
    }
  }
}

class MaxValueValidator<T> extends Validator<T> {
  final num maxValue;

  MaxValueValidator(this.maxValue);

  @override
  Future<void> validate(T? value) async {
    if (value != null && num.parse(value.toString()) > maxValue) {
      throw ValidationError({
        'max_value': ["Ensure this value is less than or equal to $maxValue."],
      });
    }
  }
}

class MinValueValidator<T> extends Validator<T> {
  final num minValue;

  MinValueValidator(this.minValue);

  @override
  Future<void> validate(T? value) async {
    if (value != null && num.parse(value.toString()) < minValue) {
      throw ValidationError({
        'min_value': [
          "Ensure this value is greater than or equal to $minValue.",
        ],
      });
    }
  }
}

class StepValueValidator<T> extends Validator<T> {
  final num stepSize;
  final num? offset;

  StepValueValidator(this.stepSize, {this.offset});

  @override
  Future<void> validate(T? value) async {
    if (value != null) {
      final numValue = num.parse(value.toString());
      final adjustedValue = offset != null ? numValue - offset! : numValue;
      if (adjustedValue % stepSize != 0) {
        throw ValidationError({
          'step_value': ["Ensure this value is a multiple of $stepSize."],
        });
      }
    }
  }
}

class DecimalValidator<T> extends Validator<T> {
  final int? maxDigits;
  final int? decimalPlaces;

  DecimalValidator(this.maxDigits, this.decimalPlaces);

  @override
  Future<void> validate(T? value) async {
    if (value != null && value is num) {
      final strValue = value.toString();
      final parts = strValue.split('.');
      final integerPart = parts[0];
      final decimalPart = parts.length > 1 ? parts[1] : '';

      if (maxDigits != null &&
          (integerPart.length + decimalPart.length) > maxDigits!) {
        throw ValidationError({
          'max_digits': [
            "Ensure this value has at most $maxDigits digits in total.",
          ],
        });
      }
      if (decimalPlaces != null && decimalPart.length > decimalPlaces!) {
        throw ValidationError({
          'max_digits': [
            "Ensure this value has at most $maxDigits digits in total.",
          ],
        });
      }
    }
  }
}

class ImageValidator<T> extends Validator<T> {
  @override
  Future<void> validate(T? value) async {
    // Placeholder for image-specific validation logic
    if (value == null) {
      throw ValidationError({
        'invalid_image_file': ["Invalid image file."],
      });
    }
  }
}

class URLValidator<T> extends Validator<T> {
  const URLValidator();

  @override
  Future<void> validate(T? value) async {
    final urlRegex = RegExp(
      r"^(https?|ftp):\/\/[^\s/$.?#].[^\s]*$",
      caseSensitive: false,
    );
    if (value != null && !urlRegex.hasMatch(value.toString())) {
      throw ValidationError({
        'invalid_url': ["Enter a valid URL."],
      });
    }
  }
}

class SlugValidator<T> extends Validator<T> {
  @override
  Future<void> validate(T? value) async {
    if (value != null &&
        !RegExp(r'^[-a-zA-Z0-9_]+$').hasMatch(value.toString())) {
      throw ValidationError({
        'invalid_slug': [
          "Enter a valid slug consisting of letters, numbers, underscores or hyphens.",
        ],
      });
    }
  }
}

class UnicodeSlugValidator<T> extends Validator<T> {
  @override
  Future<void> validate(T? value) async {
    if (value != null &&
        !RegExp(r'^[-\w]+$', unicode: true).hasMatch(value.toString())) {
      throw ValidationError({
        'invalid_slug': [
          "Enter a valid slug consisting of Unicode letters, numbers, underscores or hyphens.",
        ],
      });
    }
  }
}

class RegexValidator<T> extends Validator<T> {
  final RegExp regex;

  RegexValidator(this.regex);

  @override
  Future<void> validate(T? value) async {
    if (value != null && !regex.hasMatch(value.toString())) {
      throw ValidationError({
        'invalid_value': ["Enter a valid value."],
      });
    }
  }
}

class EmailValidator<T> extends Validator<T> {
  final String? customErrorMessage;
  late final _validator = acanthis.string().email();

  EmailValidator({this.customErrorMessage});

  @override
  Future<void> validate(T? value) async {
    if (value == null || value.toString().trim().isEmpty) {
      return;
    }

    final result = _validator.tryParse(value.toString());
    if (!result.success) {
      throw ValidationError({
        'invalid_email': [customErrorMessage ?? "Enter a valid email address."],
      });
    }
  }
}

// class ImageValidator<T> extends Validator<T> {
// /// Returns a list of allowed image file extensions.
// List<String> getImageExtensions() {
//   return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];
// }

// /// Validates that the given file has an allowed image extension.
// void validateImageFileExtension(String filename) {
//   final ext = filename.toLowerCase().split('.').last;
//   final allowedExts = getImageExtensions().map((e) => e.replaceAll('.', ''));
//   if (!allowedExts.contains(ext)) {
//     throw ValidationError(
//       'Upload a valid image. The file you uploaded was either not an image or a corrupted image.',
//     );
//   }
// }

//   @override
//   Future<void> validate(T? value) async {
//     // Placeholder for image-specific validation logic
//   }
// }
