import 'datetime_base_input.dart';

/// A widget for date input fields.
///
/// Renders as: `<input type="date" ...>`
class DateInput extends DateTimeBaseInput {
  DateInput({
    super.attrs,
    super.format = 'yyyy-MM-dd',
    super.templateName = 'widgets/date.html',
    super.inputType = 'date',
  });

  @override
  String formatValue(dynamic value) {
    if (value is DateTime) {
      return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    return value.toString();
  }
}
