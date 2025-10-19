import 'base_input.dart';

/// A widget for password input fields.
///
/// Renders as: `<input type="password" ...>`
class PasswordInput extends Input {
  PasswordInput({
    super.attrs,
    super.templateName = 'widgets/password.html',
    super.inputType = 'password',
  });
}
