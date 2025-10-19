import '../mixins/default_view.dart';
import 'radio_select.dart';

/// A widget for multiple checkbox select fields.
///
/// Renders as: `<input type="checkbox" ...>` with additional options.
class CheckboxSelectMultiple extends RadioSelect with DefaultView {
  CheckboxSelectMultiple({super.attrs, required super.choices})
    : super(
        optionTemplateName: 'widgets/checkbox_option.html',
        addIdIndex: false,
        checkedAttribute: const {'checked': true},
        optionInheritsAttrs: false,
      );

  @override
  Future<String> renderOption(Map<String, dynamic> context) async {
    final name = context['name'] as String;
    final value = context['value'];
    final label = context['label'];
    final checked = context['selected'] as bool;
    final attrsMap = context['attrs'] as Map;
    final attrs = <String, String>{};
    attrsMap.forEach((key, value) {
      if (value is String) {
        attrs[key.toString()] = value;
      } else if (value is bool && value) {
        attrs[key.toString()] = '';
      } else {
        attrs[key.toString()] = value.toString();
      }
    });

    if (checked) {
      attrs['checked'] = '';
    }

    final attrsString = attrs.isEmpty
        ? ''
        : ' ${attrs.entries.map((e) => e.value.isEmpty ? e.key : '${e.key}="${e.value}"').join(' ')}';

    final html =
        '''
      <div>
        <input type="checkbox" name="$name" value="$value"$attrsString>
        <label>$label</label>
      </div>
    '''
            .trim();
    return html;
  }

  @override
  String? get templateName => 'widgets/checkbox_select.html';

  @override
  bool get allowMultipleSelected => true;

  @override
  bool useRequiredAttribute(dynamic initial) {
    // Don't use the 'required' attribute because browser validation would
    // require all checkboxes to be checked instead of at least one.
    return false;
  }

  @override
  bool valueOmittedFromData(Map<String, dynamic> data, String name) {
    // HTML checkboxes don't appear in POST data if not checked, so it's
    // never known if the value is actually omitted.
    return false;
  }

  @override
  List<String> formatValue(dynamic value) {
    if (value == null) return [];
    if (value is! List) {
      value = [value];
    }
    return value.map((v) => v?.toString() ?? '').toList();
  }
}
