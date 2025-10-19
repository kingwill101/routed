import '../text_input.dart';

/// Base class for date and time input widgets.
///
/// This class provides common functionality for date and time input widgets.
abstract class DateTimeBaseInput extends TextInput {
  final String format;

  DateTimeBaseInput({
    super.attrs,
    required this.format,
    required super.templateName,
    required super.inputType,
  });

  @override
  Map<String, dynamic> getContext(
    String name,
    dynamic value, [
    Map<String, dynamic>? extraAttrs,
  ]) {
    final Map<String, String> combinedAttrs = {...?extraAttrs};
    combinedAttrs['format'] = format;

    final context = super.getContext(name, value, combinedAttrs);
    if (value != null) {
      context['widget']['value'] = formatValue(value);
    }
    return context;
  }

  /// Format the value for display in the input field.
  @override
  String formatValue(dynamic value);
}
