import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/text_input.dart';
import 'field.dart';

class SlugField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid":
        "Enter a valid 'slug' consisting of letters, numbers, underscores or hyphens.",
    "min_length": "Ensure this value has at least %(min_length)d characters.",
    "max_length": "Ensure this value has at most %(max_length)d characters.",
  };

  final bool allowUnicode;
  final dynamic emptyValue;
  final int? minLength;
  final int? maxLength;

  // ASCII slug only allows letters, numbers, underscores, and hyphens
  static final _asciiSlugRegex = RegExp(r'^[-a-zA-Z0-9_]+$');

  // Unicode slug allows any word character (includes letters from any language) and hyphens
  static final _unicodeSlugRegex = RegExp(
    r'^(?:[-\p{L}\p{N}_])+$',
    unicode: true,
  );

  SlugField({
    String? name,
    this.allowUnicode = false,
    this.emptyValue = '',
    this.minLength,
    this.maxLength,
    Widget? widget,
    Widget? hiddenWidget,
    List<Validator<T>>? validators,
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
  }) : super(
         name: name ?? '',
         widget: widget ?? TextInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         validators: [
           if (minLength != null) MinLengthValidator<T>(minLength),
           if (maxLength != null) MaxLengthValidator<T>(maxLength),
           ...?validators,
         ],
         errorMessages: {
           "required": "This field is required.",
           "invalid": allowUnicode
               ? "Enter a valid 'slug' consisting of Unicode letters, numbers, underscores or hyphens."
               : "Enter a valid 'slug' consisting of letters, numbers, underscores or hyphens.",
           "min_length":
               "Ensure this value has at least %(min_length)d characters.",
           "max_length":
               "Ensure this value has at most %(max_length)d characters.",
           ...?errorMessages,
         },
       );

  @override
  T? toDart(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return emptyValue as T?;
    }

    final slug = value.toString().trim();
    final regex = allowUnicode ? _unicodeSlugRegex : _asciiSlugRegex;

    if (!regex.hasMatch(slug)) {
      throw ValidationError({
        'invalid': [
          errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
        ],
      });
    }

    return slug as T;
  }
}
