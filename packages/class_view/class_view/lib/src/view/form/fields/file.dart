import 'dart:typed_data' show Uint8List;

import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/file_input.dart';
import '../widgets/hidden_input.dart';
import 'field.dart';

/// Interface for file objects used in forms.
///
/// This interface defines the minimum required properties that a file object
/// must have to be used with [FileField].
abstract class FormFile {
  /// The name of the file.
  String name;

  /// The size of the file in bytes.
  int size;

  /// The content type (MIME type) of the file.
  String contentType;

  /// The content of the file.
  Uint8List content;

  FormFile({
    required this.name,
    required this.size,
    required this.contentType,
    required this.content,
  });
}

/// A form field that handles file uploads.
///
/// The field accepts any type that implements [FormFile] interface.
/// It validates file attributes like size, name length, and content type.
class FileField<T extends FormFile> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid": "No file was submitted. Check the encoding type on the form.",
    "missing": "No file was submitted.",
    "empty": "The submitted file is empty.",
    "max_length":
        "Ensure this filename has at most %(max)d characters (it has %(length)d).",
    "max_size": "File size exceeds maximum allowed size.",
    "content_type": "Files of type %(content_type)s are not supported.",
  };

  final int? maxLength;
  final int? maxSize;
  final List<String>? allowedTypes;
  final bool allowEmptyFile;

  FileField({
    String? name,
    this.maxLength,
    this.maxSize,
    this.allowedTypes,
    this.allowEmptyFile = false,
    Widget? widget,
    Widget? hiddenWidget,
    super.validators,
    super.required = true,
    super.label,
    super.initial,
    super.helpText,
    Map<String, String>? errorMessages,
    super.showHiddenInitial,
    super.localize,
    super.disabled,
    super.labelSuffix,
    super.templateName,
  }) : super(
         name: name ?? '',
         widget: widget ?? FileInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid":
                 "No file was submitted. Check the encoding type on the form.",
             "missing": "No file was submitted.",
             "empty": "The submitted file is empty.",
             "max_length":
                 "Ensure this filename has at most %(max)d characters (it has %(length)d).",
             "max_size": "File size exceeds maximum allowed size.",
             "content_type":
                 "Files of type %(content_type)s are not supported.",
           },
           ...?errorMessages,
         },
       );

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

    // Check if value is a valid file object
    if (value is! T) {
      throw ValidationError({
        'invalid': [
          errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
        ],
      });
    }

    final file = value;
    final String fileName = file.name;
    final int fileSize = file.size;
    final String fileContentType = file.contentType.toLowerCase();

    // Check empty file name first
    if (fileName.isEmpty) {
      throw ValidationError({
        'invalid': [
          errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
        ],
      });
    }

    // Check filename length
    if (maxLength != null && fileName.length > maxLength!) {
      throw ValidationError({
        'max_length': [
          (errorMessages?["max_length"]
                      ?.replaceAll("%(max)d", maxLength.toString())
                      .replaceAll("%(length)d", fileName.length.toString()) ??
                  defaultErrorMessages["max_length"]!)
              .replaceAll("%(max)d", maxLength.toString())
              .replaceAll("%(length)d", fileName.length.toString()),
        ],
      });
    }

    // Check file size
    if (!allowEmptyFile && fileSize == 0) {
      throw ValidationError({
        'empty': [errorMessages?["empty"] ?? defaultErrorMessages["empty"]!],
      });
    }

    if (maxSize != null && fileSize > maxSize!) {
      throw ValidationError({
        'max_size': [
          (errorMessages?["max_size"] ?? defaultErrorMessages["max_size"]!)
              .replaceAll("%(max)d", maxSize.toString())
              .replaceAll("%(size)d", fileSize.toString()),
        ],
      });
    }

    // Check content type
    if (allowedTypes != null && !allowedTypes!.contains(fileContentType)) {
      throw ValidationError({
        'content_type': [
          (errorMessages?["content_type"]?.replaceAll(
                    "%(content_type)s",
                    fileContentType,
                  ) ??
                  defaultErrorMessages["content_type"]!)
              .replaceAll("%(content_type)s", fileContentType),
        ],
      });
    }

    return file;
  }

  @override
  bool hasChanged(dynamic initial, dynamic data) {
    if (disabled) return false;
    return data != null;
  }
}
