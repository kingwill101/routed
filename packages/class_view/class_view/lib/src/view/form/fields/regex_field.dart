import '../validation.dart';
import 'char.dart';

/// A field that validates its input against a regular expression.
class RegexField extends CharField<String> {
  /// The regular expression to validate against.
  RegExp regex;

  @override
  Map<String, String> get defaultErrorMessages => {
    ...super.defaultErrorMessages,
    "invalid": "Enter a valid value.",
  };

  /// Creates a new [RegexField].
  ///
  /// The [pattern] can be either a [String] or a [RegExp]. If a [String] is
  /// provided, it will be converted to a [RegExp].
  ///
  /// If [unicode] is true, the pattern will be compiled with the unicode flag.
  /// If [stripValue] is true, leading and trailing whitespace will be removed.
  /// If [required] is false, empty values will be allowed.
  /// If [emptyValue] is provided, it will be used as the value for empty inputs.
  /// If [minLength] is provided, the input must be at least that many characters.
  /// If [maxLength] is provided, the input must be at most that many characters.
  RegexField(
    dynamic pattern, {
    bool unicode = false,
    super.stripValue,
    super.required,
    super.emptyValue,
    super.minLength,
    super.maxLength,
    List<Validator<String>>? validators,
    Map<String, String>? errorMessages,
  }) : regex = pattern is RegExp
           ? pattern
           : RegExp(pattern as String, unicode: unicode),
       super(validators: [...?validators], errorMessages: {...?errorMessages}) {
    super.validators.add(RegexValidator<String>(regex));
  }

  @override
  String? toDart(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return emptyValue ? '' : null;
    }
    return super.toDart(value);
  }

  @override
  Future<void> validate(String? value) async {
    await super.validate(value);
    if (value != null && value.isNotEmpty) {
      if (!regex.hasMatch(value)) {
        throw ValidationError({
          'invalid': [
            errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
          ],
        });
      }
    }
  }
}
