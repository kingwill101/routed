import 'choice_widget.dart';

/// A widget for radio button fields.
///
/// Renders as: `<input type="radio">` for each choice
class RadioSelect extends ChoiceWidget {
  RadioSelect({
    super.attrs,
    required super.choices,
    super.optionTemplateName = 'widgets/radio_option.html',
    super.addIdIndex = false,
    super.checkedAttribute = const {'checked': true},
    super.optionInheritsAttrs = false,
  }) : super(inputType: 'radio');

  @override
  String? get templateName => 'widgets/radio.html';

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

    return '''
      <div>
        <input type="radio" name="$name" value="$value"$attrsString>
        <label>$label</label>
      </div>
    '''
        .trim();
  }

  Future<String> renderOptions(
    List<(String?, List<Map<String, dynamic>>, Map<String, dynamic>)> optgroups,
    Map<String, dynamic> attrs,
    dynamic value,
    String name,
  ) async {
    final buffer = StringBuffer();

    for (final (label, options, groupAttrs) in optgroups) {
      if (label != null) {
        final attrsString = groupAttrs.isEmpty
            ? ''
            : ' ${groupAttrs.entries.map((e) => '${e.key}="${e.value}"').join(' ')}';
        buffer.write('<div class="radio-group" role="group"$attrsString>');
        buffer.write('<label>$label</label>');
      }

      for (final option in options) {
        final attrsForOption = <String, String>{};
        if (optionInheritsAttrs) {
          attrs.forEach((key, value) {
            if (value is String) {
              attrsForOption[key] = value;
            } else if (value is bool && value) {
              attrsForOption[key] = '';
            } else {
              attrsForOption[key] = value.toString();
            }
          });
        }
        final optionContext = {
          'name': name,
          'value': option['value'],
          'label': option['label'],
          'selected': option['selected'] as bool,
          'attrs': attrsForOption,
        };
        buffer.write(await renderOption(optionContext));
      }

      if (label != null) {
        buffer.write('</div>');
      }
    }

    return buffer.toString();
  }

  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final widget = context['widget'] as Map<String, dynamic>;
    final name = widget['name'] as String;
    final attrsMap = widget['attrs'] as Map;
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
    final optgroups =
        widget['optgroups']
            as List<
              (String?, List<Map<String, dynamic>>, Map<String, dynamic>)
            >;
    final value = widget['value'];

    return renderOptions(
      optgroups,
      optionInheritsAttrs ? attrs : const {},
      value,
      name,
    );
  }
}
