import 'base_input.dart';

/// A widget for hidden input fields.
///
/// Renders as: `<input type="hidden" ...>`
class HiddenInput extends Input {
  HiddenInput({
    super.attrs,
    super.templateName = 'widgets/hidden.html',
    super.inputType = 'hidden',
  });

  @override
  bool get isHidden => true;
}
