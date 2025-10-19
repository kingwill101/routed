import '../validation.dart';
import '../widgets/file_input.dart';
import 'file.dart';

class MultipleFileInput extends FileInput {}

class MultipleFileField<T extends FormFile> extends FileField<T> {
  MultipleFileField({
    super.maxLength,
    super.maxSize,
    super.allowedTypes,
    super.allowEmptyFile = false,
    super.required = true,
    super.label,
    super.initial,
    super.helpText,
    super.errorMessages,
    super.disabled,
  }) : super(widget: MultipleFileInput());

  @override
  T? toDart(dynamic value) {
    if (value == null || (value is String && value.isEmpty)) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return null;
    }

    if (value is List) {
      for (final file in value) {
        super.toDart(file); // This will validate each file
      }
      return value.isNotEmpty ? super.toDart(value.first) : null;
    }

    return super.toDart(value);
  }

  List<T>? toMultipleDart(dynamic value) {
    if (value == null || (value is String && value.isEmpty)) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return null;
    }

    if (value is! List) {
      final singleFile = toDart(value);
      return singleFile != null ? [singleFile] : null;
    }

    final results = <T>[];
    for (final file in value) {
      final result = toDart(file);
      if (result != null) {
        results.add(result);
      }
    }
    return results.isEmpty ? null : results;
  }
}
