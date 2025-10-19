import 'base_input.dart';

/// A widget for file input fields.
///
/// Renders as: `<input type="file" ...>`
class FileInput extends Input {
  FileInput({super.attrs})
    : super(inputType: 'file', templateName: 'widgets/file.html');

  @override
  bool get needsMultipartForm => true;
}
