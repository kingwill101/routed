import 'datetime_base_input.dart';

/// A widget for time input fields.
///
/// Renders as: `<input type="time" ...>`
class TimeInput extends DateTimeBaseInput {
  TimeInput({
    super.attrs,
    super.format = 'HH:mm',
    super.templateName = 'widgets/time.html',
    super.inputType = 'time',
  });

  @override
  String formatValue(dynamic value) {
    if (value is DateTime) {
      return '${value.hour.toString().padLeft(2, '0')}:'
          '${value.minute.toString().padLeft(2, '0')}';
    }
    return value.toString();
  }
}
