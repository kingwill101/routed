import 'base_input.dart';

/// A widget for text input fields.
///
/// Renders as: `<input type="text" ...>`
class TextInput extends Input {
  TextInput({
    super.attrs,
    super.templateName = 'widgets/text.html',
    super.inputType = 'text',
  });
}
