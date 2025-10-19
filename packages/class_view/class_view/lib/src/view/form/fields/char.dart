import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/text_input.dart';
import 'field.dart';

class CharField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "max_length":
        "Ensure this value has at most %(max)s characters (it has %(length)s).",
    "min_length":
        "Ensure this value has at least %(min)s characters (it has %(length)s).",
    "null_characters": "Null characters are not allowed.",
  };

  final int? maxLength;
  final int? minLength;
  final bool stripValue;
  final bool emptyValue;
  final bool normalizeLineEndings;
  final List<dynamic> emptyValues;

  CharField({
    String? name,
    this.maxLength,
    this.minLength,
    this.stripValue = true,
    this.emptyValue = false,
    this.normalizeLineEndings = true,
    this.emptyValues = const [null, '', []],
    Widget? widget,
    Widget? hiddenWidget,
    super.validators,
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
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "max_length":
                 "Ensure this value has at most %(max)s characters (it has %(length)s).",
             "min_length":
                 "Ensure this value has at least %(min)s characters (it has %(length)s).",
             "null_characters": "Null characters are not allowed.",
           },
           ...?errorMessages,
         },
       );

  bool _isEmptyValue(dynamic value) {
    if (value == null) return true;
    if (value is String && value.isEmpty) return true;
    return emptyValues.any(
      (empty) =>
          empty == value ||
          (empty is String && value is String && empty == value) ||
          (empty is List && value is List && empty.length == value.length) ||
          (empty is Map && value is Map && empty.length == value.length),
    );
  }

  @override
  T? toDart(dynamic value) {
    // Handle empty values
    if (_isEmptyValue(value)) {
      return emptyValue ? '' as T : null;
    }

    String stringValue = value.toString();

    // Strip whitespace if configured
    if (stripValue) {
      stringValue = stringValue.trim();
    }

    // Normalize line endings if configured
    if (normalizeLineEndings) {
      stringValue = stringValue.replaceAll(RegExp(r'\r\n|\r'), '\n');
    }

    return stringValue as T;
  }

  @override
  Future<void> validate(T? value) async {
    await super.validate(value);

    if (value == null || value.toString().isEmpty) {
      return;
    }

    final stringValue = value.toString();

    // Check for null characters
    if (stringValue.contains('\x00')) {
      throw ValidationError({
        'null_characters': [
          errorMessages?["null_characters"] ??
              defaultErrorMessages["null_characters"]!,
        ],
      });
    }

    // Validate max length
    if (maxLength != null && stringValue.length > maxLength!) {
      throw ValidationError({
        'max_length': [
          (errorMessages?["max_length"] ?? defaultErrorMessages["max_length"]!)
              .replaceAll("%(max)s", maxLength.toString())
              .replaceAll("%(length)s", stringValue.length.toString()),
        ],
      });
    }

    // Validate min length
    if (minLength != null && stringValue.length < minLength!) {
      throw ValidationError({
        'min_length': [
          (errorMessages?["min_length"] ?? defaultErrorMessages["min_length"]!)
              .replaceAll("%(min)s", minLength.toString())
              .replaceAll("%(length)s", stringValue.length.toString()),
        ],
      });
    }
  }

  @override
  Map<String, dynamic> widgetAttrs(Widget widget) {
    final attrs = super.widgetAttrs(widget);
    if (maxLength != null && !widget.isHidden) {
      attrs["maxlength"] = maxLength.toString();
    }
    if (minLength != null && !widget.isHidden) {
      attrs["minlength"] = minLength.toString();
    }
    return attrs;
  }
}
