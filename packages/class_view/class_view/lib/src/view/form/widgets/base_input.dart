import '../mixins/default_view.dart';
import 'base_widget.dart';

/// Base class for all `<input>` widgets.
///
/// This class provides common functionality for input widgets, such as
/// rendering and handling attributes.
abstract class Input extends Widget with DefaultView {
  /// The input type (e.g., text, number, email, etc.).
  String inputType;

  Input({required this.inputType, super.attrs, super.templateName});

  @override
  Map<String, dynamic> getContext(
    String name,
    dynamic value, [
    Map<String, dynamic>? extraAttrs,
  ]) {
    final Map<String, dynamic> context = super.getContext(
      name,
      value,
      extraAttrs,
    );
    context['widget'] ??= <String, dynamic>{};
    context['widget']['type'] = inputType;
    return context;
  }

  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final buffer = StringBuffer();
    final widget = context['widget'] as Map<String, dynamic>;
    final name = widget['name'] as String;
    final value = widget['value'];
    final attrs = widget['attrs'] as Map<String, dynamic>;
    final type = widget['type'] as String;

    buffer.write('<input type="$type" name="$name"');

    // Always include value attribute, even for empty strings
    buffer.write(' value="${value ?? ''}"');

    // Handle attributes
    if (attrs.isNotEmpty) {
      for (final entry in attrs.entries) {
        final attrValue = entry.value.toString();
        if (attrValue.isEmpty || attrValue == entry.key) {
          buffer.write(' ${entry.key}');
        } else {
          buffer.write(' ${entry.key}="$attrValue"');
        }
      }
    }

    buffer.write('>');
    return buffer.toString();
  }
}
