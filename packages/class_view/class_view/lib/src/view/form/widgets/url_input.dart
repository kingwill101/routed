import 'base_input.dart';

/// A widget for URL input fields.
///
/// Renders as: `<input type="url" ...>`
class URLInput extends Input {
  URLInput({
    Map<String, String>? attrs,
    super.templateName = 'widgets/url.html',
    super.inputType = 'url',
    int? maxLength,
    int? minLength,
  }) : super(
         attrs: {
           ...?attrs,
           if (maxLength != null) 'maxlength': maxLength.toString(),
           if (minLength != null) 'minlength': minLength.toString(),
         },
       );
}
