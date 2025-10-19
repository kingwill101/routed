import 'choice_widget.dart';

/// A widget for select fields.
///
/// Renders as: `<select>...</select>`
class Select extends ChoiceWidget {
  @override
  final List<List<dynamic>> choices;
  final bool multiple;

  Select({
    super.attrs,
    required this.choices,
    this.multiple = false,
    super.allowMultipleSelected = false,
    super.optionTemplateName = 'widgets/select_option.html',
    super.addIdIndex = false,
    super.checkedAttribute = const {'selected': true},
    super.optionInheritsAttrs = false,
  }) : super(inputType: 'select');

  @override
  String? get templateName => 'widgets/select.html';

  @override
  Map<String, dynamic> getContext(
    String name,
    dynamic value, [
    Map<String, dynamic>? extraAttrs,
  ]) {
    final context = super.getContext(name, value, extraAttrs);
    if (multiple) {
      context['widget']['attrs']['multiple'] = 'multiple';
    }
    return context;
  }

  static bool _choiceHasEmptyValue(List<dynamic> choice) {
    // Return true if the choice's value is an empty string or null.
    final value = choice[0];
    return value == null || value == '';
  }

  @override
  bool useRequiredAttribute(dynamic initial) {
    // Don't render 'required' if the first <option> has a value, as that's invalid HTML.
    final useRequired = super.useRequiredAttribute(initial);
    if (multiple) {
      return useRequired;
    }

    final firstChoice = choices.isNotEmpty ? choices.first : null;
    return useRequired &&
        firstChoice != null &&
        _choiceHasEmptyValue(firstChoice);
  }

  Future<String> renderOption(Map<String, dynamic> context) async {
    final selected = context['selected'] as bool;
    final value = context['value'];
    final label = context['label'];
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

    if (selected) {
      attrs['selected'] = '';
    }

    final attrsString = attrs.isEmpty
        ? ''
        : ' ${attrs.entries.map((e) => e.value.isEmpty ? e.key : '${e.key}="${e.value}"').join(' ')}';

    return '<option value="$value"$attrsString>$label</option>';
  }

  Future<String> renderOptions(
    List<(String?, List<Map<String, dynamic>>, Map<String, dynamic>)> optgroups,
    Map<String, dynamic> attrs,
    dynamic value,
  ) async {
    final buffer = StringBuffer();

    for (final (label, options, groupAttrs) in optgroups) {
      if (label != null) {
        final attrsString = groupAttrs.isEmpty
            ? ''
            : ' ${groupAttrs.entries.map((e) => '${e.key}="${e.value}"').join(' ')}';
        buffer.write('<optgroup label="$label"$attrsString>');
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
          'value': option['value'],
          'label': option['label'],
          'selected': option['selected'] as bool,
          'attrs': attrsForOption,
        };
        buffer.write(await renderOption(optionContext));
      }

      if (label != null) {
        buffer.write('</optgroup>');
      }
    }

    return buffer.toString();
  }

  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final buffer = StringBuffer();
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

    // Render opening tag
    buffer.write('<select name="$name"');
    if (multiple) {
      buffer.write(' multiple');
    }
    if (attrs.isNotEmpty) {
      buffer.write(
        ' ${attrs.entries.map((e) => '${e.key}="${e.value}"').join(' ')}',
      );
    }
    buffer.write('>');

    // Render options
    buffer.write(
      await renderOptions(
        optgroups,
        optionInheritsAttrs ? attrs : const {},
        value,
      ),
    );

    // Render closing tag
    buffer.write('</select>');

    return buffer.toString();
  }

  // ignore: unused_element
  bool _isValueSelected(dynamic optionValue, dynamic value) {
    if (value == null) return false;
    if (multiple && value is List) {
      return value.any((v) => v.toString() == optionValue.toString());
    }
    return value.toString() == optionValue.toString();
  }
}
