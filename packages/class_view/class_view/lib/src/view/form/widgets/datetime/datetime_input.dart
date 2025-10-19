import 'datetime_base_input.dart';

/// A widget for datetime-local input fields.
///
/// Renders as: `<input type="datetime-local" ...>`
class DateTimeInput extends DateTimeBaseInput {
  DateTimeInput({
    super.attrs,
    super.format = 'yyyy-MM-ddTHH:mm',
    super.templateName = 'widgets/datetime.html',
    super.inputType = 'datetime-local',
  });

  @override
  String formatValue(dynamic value) {
    if (value is DateTime) {
      return '${value.year}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}T'
          '${value.hour.toString().padLeft(2, '0')}:'
          '${value.minute.toString().padLeft(2, '0')}';
    }
    return value.toString();
  }
}
