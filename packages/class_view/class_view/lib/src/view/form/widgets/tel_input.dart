import 'base_input.dart';

/// A widget for telephone number input fields.
///
/// Renders as: `<input type="tel" ...>`
class TelInput extends Input {
  TelInput({
    super.attrs,
    super.templateName = 'widgets/tel.html',
    super.inputType = 'tel',
  });
}
