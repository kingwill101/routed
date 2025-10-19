import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/hidden_input.dart';
import '../widgets/url_input.dart';
import 'field.dart';

class URLField extends Field<String> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid": "Enter a valid URL.",
  };

  final int? maxLength;
  final int? minLength;
  final String assumeScheme;
  final String? emptyValue;

  static final _urlValidationRegex = RegExp(
    r'^(?:(?:http|ftp)s?://)?' // Optional scheme
    r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+(?:[A-Z]{2,6}\.?|[A-Z0-9-]{2,}\.?)|' // domain...
    r'localhost|' // localhost...
    r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|' // ...or ipv4
    r'\[?[A-F0-9]*:[A-F0-9:]+\]?)' // ...or ipv6
    r'(?::\d+)?' // optional port
    r'(?:/?|[/?][^\s]*)?$', // path
    caseSensitive: false,
  );

  URLField({
    String? name,
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
    this.maxLength,
    this.minLength,
    this.assumeScheme = 'https',
    this.emptyValue = '',
  }) : super(
         name: name ?? '',
         widget: widget ?? URLInput(maxLength: maxLength, minLength: minLength),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid": "Enter a valid URL.",
           },
           ...?errorMessages,
         },
       );

  @override
  String? toDart(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      if (required) {
        throw ValidationError({
          'required': [
            errorMessages?["required"] ?? defaultErrorMessages["required"]!,
          ],
        });
      }
      return emptyValue;
    }

    String url = value.toString().trim();

    // Validate length before URL format
    if (minLength != null && url.length < minLength!) {
      throw ValidationError({
        'min_length': [
          'Ensure this value has at least $minLength characters (it has ${url.length}).',
        ],
      });
    }

    if (maxLength != null && url.length > maxLength!) {
      throw ValidationError({
        'max_length': [
          'Ensure this value has at most $maxLength characters (it has ${url.length}).',
        ],
      });
    }

    // Validate URL format
    if (!_urlValidationRegex.hasMatch(url)) {
      throw ValidationError({
        'invalid': [
          errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
        ],
      });
    }

    try {
      // Find the first occurrence of :// to determine the main URL's scheme boundary
      final schemeIndex = url.indexOf('://');

      if (schemeIndex == -1) {
        // No scheme found, add the default scheme
        if (url.startsWith('www.')) {
          url = '$assumeScheme://$url';
        } else {
          url = '$assumeScheme://$url';
        }
      } else {
        // Check if there's a www. prefix before the scheme
        final beforeScheme = url.substring(0, schemeIndex);
        if (beforeScheme.startsWith('www.')) {
          // Remove www. and add it after the scheme
          url = '$assumeScheme://www.${url.substring(4)}';
        }
      }

      return url;
    } catch (e) {
      throw ValidationError({
        'invalid': [
          errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
        ],
      });
    }
  }

  @override
  Map<String, dynamic> widgetAttrs(Widget widget) {
    final attrs = super.widgetAttrs(widget);
    if (maxLength != null) {
      attrs['maxlength'] = maxLength.toString();
    }
    if (minLength != null) {
      attrs['minlength'] = minLength.toString();
    }
    return attrs;
  }
}
