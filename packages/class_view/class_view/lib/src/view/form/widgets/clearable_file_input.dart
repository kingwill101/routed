import 'file_input.dart';

/// A widget for clearable file input fields.
///
/// Renders as: `<input type="file" ...>` with additional functionality for
/// clearing the file input.
class ClearableFileInput extends FileInput {
  /// The label for the clear checkbox
  final String clearCheckboxLabel;

  /// The text to show before the current file
  final String initialText;

  /// The text to show before the file input
  final String inputText;

  /// Whether the clear checkbox is checked by default
  final bool checked;

  ClearableFileInput({
    super.attrs,
    this.clearCheckboxLabel = 'Clear',
    this.initialText = 'Currently',
    this.inputText = 'Change',
    this.checked = false,
  });

  @override
  String? get templateName => 'widgets/clearable_file_input.html';

  /// Given the name of the file input, return the name of the clear checkbox input.
  String clearCheckboxName(String name) {
    return '$name-clear';
  }

  /// Given the name of the clear checkbox input, return the HTML id for it.
  String clearCheckboxId(String name) {
    return '${clearCheckboxName(name)}_id';
  }

  /// Return whether value is considered to be initial value.
  bool isInitial(dynamic value) {
    return value != null && value.url != null;
  }

  @override
  dynamic formatValue(dynamic value) {
    // Return the file object if it has a defined url attribute.
    if (isInitial(value)) {
      return value;
    }
    return null;
  }

  @override
  Map<String, dynamic> getContext(
    String name,
    dynamic value, [
    Map<String, dynamic>? extraAttrs,
  ]) {
    final context = super.getContext(name, value, extraAttrs);
    final String checkboxName = clearCheckboxName(name);
    final String checkboxId = clearCheckboxId(name);

    context['widget'].addAll({
      'checkbox_name': checkboxName,
      'checkbox_id': checkboxId,
      'is_initial': isInitial(value),
      'input_text': inputText,
      'initial_text': initialText,
      'clear_checkbox_label': clearCheckboxLabel,
    });

    final attrs = context['widget']['attrs'] as Map<String, dynamic>;
    attrs['disabled'] ??= 'false';
    if (checked) {
      attrs['checked'] = '';
    }

    return context;
  }

  @override
  dynamic valueFromData(Map<String, dynamic> data, String name) {
    final dynamic upload = super.valueFromData(data, name);
    final bool isCleared = data.containsKey(clearCheckboxName(name));

    if (!isRequired && isCleared) {
      if (upload != null) {
        // If the user contradicts themselves (uploads a new file AND checks the "clear" checkbox),
        // return a unique marker object that FileField will turn into a ValidationError.
        return 'FILE_INPUT_CONTRADICTION';
      }
      // False signals to clear any existing value, as opposed to just null.
      return false;
    }

    return upload;
  }

  @override
  Future<String> renderDefault(Map<String, dynamic> context) async {
    final buffer = StringBuffer();
    final widget = context['widget'] as Map<String, dynamic>;
    final name = widget['name'] as String;
    final value = widget['value'];
    final attrs = widget['attrs'] as Map<String, dynamic>;
    final isInitialValue = widget['is_initial'] as bool;
    final checkboxName = widget['checkbox_name'] as String;
    final checkboxId = widget['checkbox_id'] as String;
    final initialText = widget['initial_text'] as String;
    final inputText = widget['input_text'] as String;
    final clearCheckboxLabel = widget['clear_checkbox_label'] as String;
    final type = widget['type'] as String;

    if (isInitialValue) {
      // Show current file name
      buffer.write('$initialText: $value');

      // Show clear checkbox if not required
      if (!isRequired) {
        buffer.write(
          '<input type="checkbox" name="$checkboxName" id="$checkboxId"',
        );
        if (attrs['disabled'] != null) {
          buffer.write(' disabled');
        }
        if (attrs['checked'] != null) {
          buffer.write(' checked');
        }
        buffer.write('>');
        buffer.write('<label for="$checkboxId">$clearCheckboxLabel</label>');
      }
      buffer.write('<br>');
      buffer.write('$inputText:');
    }

    // Render the file input
    buffer.write('<input type="$type" name="$name"');
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
