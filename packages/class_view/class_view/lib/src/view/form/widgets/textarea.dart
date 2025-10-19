import '../mixins/default_view.dart';
import 'base_widget.dart';

/// A widget for textarea input fields.
///
/// Renders as: `<textarea ...></textarea>`
class Textarea extends Widget with DefaultView {
  Textarea({
    Map<String, String>? attrs,
    super.templateName = 'widgets/textarea.html',
  }) : super(attrs: attrs ?? {}) {
    // Only set default attributes if they are not provided
    if (!this.attrs.containsKey('cols')) {
      this.attrs['cols'] = '40';
    }
    if (!this.attrs.containsKey('rows')) {
      this.attrs['rows'] = '10';
    }
  }

  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final buffer = StringBuffer();
    buffer.write('<textarea name="${context['widget']['name']}"');

    final attrs = context['widget']['attrs'] as Map<String, dynamic>;
    attrs.forEach((String key, dynamic value) {
      if (value != null) {
        buffer.write(' $key="$value"');
      }
    });

    buffer.write('>');
    if (context['widget']['value'] != null) {
      buffer.write(context['widget']['value']);
    }
    buffer.write('</textarea>');
    return buffer.toString();
  }
}
