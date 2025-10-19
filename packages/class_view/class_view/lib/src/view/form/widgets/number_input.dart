import 'base_input.dart';

/// A widget for number input fields.
///
/// Renders as: `<input type="number" ...>`
class NumberInput extends Input {
  NumberInput({
    super.attrs,
    super.templateName = 'widgets/number.html',
    super.inputType = 'number',
  });
}
