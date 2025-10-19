import 'package:meta/meta.dart';

import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/file_input.dart';
import '../widgets/hidden_input.dart';
import 'field.dart';
import 'file.dart' show FormFile;

const String _missingImageFieldMessage =
    'ImageField support now lives in the optional '
    '`class_view_image_field` package. Add a dependency on '
    '`class_view_image_field` and import '
    '`package:class_view_image_field/class_view_image_field.dart` to enable '
    'image validation.';

typedef ImageFieldBuilder =
    ImageField Function({
      String? name,
      int? maxLength,
      int? maxSize,
      List<String>? allowedExtensions,
      Widget? widget,
      Widget? hiddenWidget,
      List<Validator<ImageFormFile>>? validators,
      bool required,
      String? label,
      ImageFormFile? initial,
      String? helpText,
      Map<String, String>? errorMessages,
      bool showHiddenInitial,
      bool localize,
      bool disabled,
      String? labelSuffix,
      String? templateName,
    });

ImageFieldBuilder _imageFieldBuilder =
    ({
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
    }) => _MissingImageField(
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

/// Register a concrete [ImageField] implementation.
void registerImageFieldBuilder(ImageFieldBuilder builder) {
  _imageFieldBuilder = builder;
}

/// Reset the image field builder to the default placeholder (for tests).
@visibleForTesting
void resetImageFieldBuilder() {
  _imageFieldBuilder =
      ({
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
      }) => _MissingImageField(
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

/// Message used when image support is missing.
String get missingImageFieldMessage => _missingImageFieldMessage;

class ImageFormFile extends FormFile {
  ImageFormFile({
    required super.name,
    required super.contentType,
    required super.size,
    required super.content,
    this.image,
  });

  /// Implementation-defined decoded image representation.
  final Object? image;

  /// Convenience alias for implementations that renamed the property.
  Object? get decoded => image;
}

class ImageField extends Field<ImageFormFile> {
  ImageField.protected({
    String? name,
    this.maxLength,
    this.maxSize,
    List<String>? allowedExtensions,
    Widget? widget,
    Widget? hiddenWidget,
    List<Validator<ImageFormFile>>? validators,
    super.required,
    super.label,
    super.initial,
    super.helpText,
    Map<String, String>? errorMessages,
    super.showHiddenInitial,
    super.localize,
    super.disabled,
    super.labelSuffix,
    super.templateName,
  }) : allowedExtensions = List.unmodifiable(
         allowedExtensions ??
             const ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
       ),
       super(
         name: name ?? '',
         widget: widget ?? FileInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         validators: validators ?? const [],
         errorMessages: {..._defaultErrorMessages, ...?errorMessages},
       );

  factory ImageField({
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
    return _imageFieldBuilder(
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

  final int? maxLength;
  final int? maxSize;
  final List<String> allowedExtensions;

  static const Map<String, String> _defaultErrorMessages = {
    "required": "This field is required.",
    "invalid":
        "Upload a valid image. The file you uploaded was either not an image or a corrupted image.",
    "missing": "No file was submitted.",
    "empty": "The submitted file is empty.",
    "max_length":
        "Ensure this filename has at most %(max)d characters (it has %(length)d).",
    "max_size": "Image file size exceeds maximum allowed size.",
    "invalid_image":
        "Upload a valid image. The file you uploaded was either not an image or a corrupted image.",
    "invalid_extension": "File extension \"%(extension)s\" is not allowed.",
  };

  @override
  Map<String, dynamic> widgetAttrs(Widget widget) {
    if (widget is FileInput) {
      final attrs = widget.attrs;
      if (attrs['accept'] != false && !attrs.containsKey('accept')) {
        return {'accept': 'image/*'};
      }
    }
    return {};
  }

  @override
  Future<ImageFormFile?> clean(dynamic value) async {
    throw UnsupportedError(_missingImageFieldMessage);
  }
}

class _MissingImageField extends ImageField {
  _MissingImageField({
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
  }) : super.protected() {
    throw UnsupportedError(_missingImageFieldMessage);
  }

  @override
  Future<ImageFormFile?> clean(dynamic value) async {
    throw UnsupportedError(_missingImageFieldMessage);
  }
}
