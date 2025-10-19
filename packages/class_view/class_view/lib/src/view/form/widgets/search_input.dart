import 'base_input.dart';

/// A widget for search input fields.
///
/// Renders as: `<input type="search" ...>`
class SearchInput extends Input {
  SearchInput({
    super.attrs,
    super.templateName = 'widgets/search.html',
    super.inputType = 'search',
  });
}
