import 'base_input.dart';

/// A widget for email input fields.
///
/// Renders as: `<input type="email" ...>`
class EmailInput extends Input {
  EmailInput({
    super.attrs,
    super.templateName = 'widgets/email.html',
    super.inputType = 'email',
  });
}
