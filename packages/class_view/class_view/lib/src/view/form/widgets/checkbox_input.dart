import '../mixins/default_view.dart';
import 'base_input.dart';

/// A widget for checkbox input fields.
///
/// Renders as: `<input type="checkbox" ...>`
class CheckboxInput extends Input with DefaultView {
  /// Optional function to test whether a value should be considered checked
  final bool Function(dynamic)? checkTest;

  CheckboxInput({super.attrs, this.checkTest})
    : super(inputType: 'checkbox', templateName: 'widgets/checkbox.html');

  @override
  dynamic formatValue(dynamic value) {
    // Only return the 'value' attribute if value isn't empty.
    if (value == true || value == false || value == null || value == '') {
      return null;
    }
    return value.toString();
  }

  @override
  Map<String, dynamic> getContext(
    String name,
    dynamic value, [
    Map<String, dynamic>? extraAttrs,
  ]) {
    final context = super.getContext(name, value, extraAttrs);
    if ((checkTest ?? (v) => v == true)(value)) {
      final attrs = context['widget']['attrs'] as Map<String, dynamic>;
      attrs['checked'] = '';
    }
    return context;
  }

  @override
  dynamic valueFromData(Map<String, dynamic> data, String name) {
    if (!data.containsKey(name)) {
      // A missing value means False because HTML form submission does not
      // send results for unselected checkboxes.
      return false;
    }
    dynamic value = data[name];
    // Translate true and false strings to boolean values.
    const values = {'true': true, 'false': false};
    if (value is String) {
      value = values[value.toLowerCase()] ?? value;
    }
    return value == true;
  }

  @override
  bool valueOmittedFromData(Map<String, dynamic> data, String name) {
    // HTML checkboxes don't appear in POST data if not checked, so it's
    // never known if the value is actually omitted.
    return false;
  }
}
