import 'hidden_input.dart';

/// A widget for multiple hidden input fields.
///
/// Renders as multiple `<input type="hidden" ...>` elements
class MultipleHiddenInput extends HiddenInput {
  MultipleHiddenInput({
    super.attrs,
    super.templateName = 'widgets/multiple_hidden.html',
    super.inputType = 'hidden',
  });

  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final buffer = StringBuffer();
    final value = context['widget']['value'];
    final name = context['widget']['name'];

    if (value is List) {
      for (final item in value) {
        buffer.write('<input type="hidden" name="$name" value="$item"');
        (context['widget']['attrs'] as Map<String, dynamic>).forEach((
          String key,
          dynamic value,
        ) {
          buffer.write(' $key="$value"');
        });
        buffer.write('>\n');
      }
    }
    return buffer.toString();
  }
}
