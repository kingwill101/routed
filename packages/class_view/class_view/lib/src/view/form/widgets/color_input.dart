import 'base_input.dart';

/// A widget for color input fields.
///
/// Renders as: `<input type="color" ...>`
class ColorInput extends Input {
  ColorInput({
    super.attrs,
    super.templateName = 'widgets/color.html',
    super.inputType = 'color',
  });
}
