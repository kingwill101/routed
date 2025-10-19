export 'package:class_view/class_view.dart'
    show
        ImageField,
        ImageFormFile,
        registerImageFieldBuilder,
        resetImageFieldBuilder;

import 'package:class_view/class_view.dart';
import 'package:image/image.dart' as img;

ImageField _buildImageField({
  String? name,
  int? maxLength,
  int? maxSize,
  List<String>? allowedExtensions,
  Widget? widget,
  Widget? hiddenWidget,
  List<Validator<ImageFormFile>>? validators,
  bool required = true,
  String? label,
  ImageFormFile? initial,
  String? helpText,
  Map<String, String>? errorMessages,
  bool showHiddenInitial = false,
  bool localize = false,
  bool disabled = false,
  String? labelSuffix,
  String? templateName,
}) {
  return _ImageFieldImpl(
    name: name,
    maxLength: maxLength,
    maxSize: maxSize,
    allowedExtensions: allowedExtensions,
    widget: widget,
    hiddenWidget: hiddenWidget,
    validators: validators,
    required: required,
    label: label,
    initial: initial,
    helpText: helpText,
    errorMessages: errorMessages,
    showHiddenInitial: showHiddenInitial,
    localize: localize,
    disabled: disabled,
    labelSuffix: labelSuffix,
    templateName: templateName,
  );
}

/// Ensure the class_view ImageField delegates to the image implementation.
void ensureImageFieldSupport() {
  registerImageFieldBuilder(_buildImageField);
}

// Register at import time.
// ignore: unused_element
final _ = (() {
  ensureImageFieldSupport();
  return true;
})();

class _ImageFieldImpl extends ImageField {
  _ImageFieldImpl({
    super.name,
    super.maxLength,
    super.maxSize,
    super.allowedExtensions,
    super.widget,
    super.hiddenWidget,
    super.validators,
    super.required,
    super.label,
    super.initial,
    super.helpText,
    super.errorMessages,
    super.showHiddenInitial,
    super.localize,
    super.disabled,
    super.labelSuffix,
    super.templateName,
  }) : super.protected();

  @override
  Future<ImageFormFile?> clean(dynamic value) async {
    if (value == null) {
      return null;
    }

    if (value is! FormFile) {
      throw ValidationError({
        'invalid': [
          errorMessages?['invalid'] ??
              'Upload a valid image. The value provided was not a file.',
        ],
      });
    }

    final file = value;

    if (maxLength != null && file.name.length > maxLength!) {
      throw ValidationError({
        'max_length': [
          (errorMessages?['max_length'] ??
                  'Ensure this filename has at most %(max)d characters (it has %(length)d).')
              .replaceAll('%(max)d', maxLength.toString())
              .replaceAll('%(length)d', file.name.length.toString()),
        ],
      });
    }

    if (maxSize != null && file.size > maxSize!) {
      throw ValidationError({
        'max_size': [
          errorMessages?['max_size'] ??
              'Image file size exceeds maximum allowed size.',
        ],
      });
    }

    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    if (!allowedExtensions.contains(extension)) {
      throw ValidationError({
        'invalid_extension': [
          (errorMessages?['invalid_extension'] ??
                  'File extension "%(extension)s" is not allowed.')
              .replaceAll('%(extension)s', extension),
        ],
      });
    }

    img.Image? decoded;
    try {
      decoded = img.decodeImage(file.content);
    } catch (_) {
      decoded = null;
    }

    if (decoded == null) {
      throw ValidationError({
        'invalid_image': [
          errorMessages?['invalid_image'] ??
              'Upload a valid image. The file you uploaded was either not an image or a corrupted image.',
        ],
      });
    }

    return ImageFormFile(
      name: file.name,
      contentType: file.contentType,
      size: file.size,
      content: file.content,
      image: decoded,
    );
  }
}
