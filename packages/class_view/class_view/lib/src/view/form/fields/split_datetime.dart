import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/datetime/date_input.dart';
import '../widgets/hidden_input.dart';
import 'field.dart';

class SplitDateTimeField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid_date": "Enter a valid date.",
    "invalid_time": "Enter a valid time.",
  };

  final Field<DateTime> dateField;
  final Field<DateTime> timeField;

  SplitDateTimeField({
    String? name,
    required this.dateField,
    required this.timeField,
    Widget? widget,
    Widget? hiddenWidget,
    super.validators,
    super.required,
    super.label,
    super.initial,
    super.helpText,
    Map<String, String>? errorMessages,
    super.showHiddenInitial,
    super.localize,
    super.disabled,
    super.labelSuffix,
    super.templateName,
  }) : super(
         name: name ?? '',
         widget: widget ?? DateInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid_date": "Enter a valid date.",
             "invalid_time": "Enter a valid time.",
           },
           ...?errorMessages,
         },
       );

  @override
  T? toDart(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return null;
    }

    final parts = value.toString().split(' ');
    if (parts.length != 2) {
      throw ValidationError({
        'invalid_date': [
          errorMessages?["invalid_date"] ??
              defaultErrorMessages["invalid_date"]!,
        ],
      });
    }

    DateTime? date;
    DateTime? time;

    try {
      date = dateField.toDart(parts[0]);
    } catch (e) {
      throw ValidationError({
        'invalid_date': [
          errorMessages?["invalid_date"] ??
              defaultErrorMessages["invalid_date"]!,
        ],
      });
    }

    try {
      time = timeField.toDart(parts[1]);
    } catch (e) {
      throw ValidationError({
        'invalid_time': [
          errorMessages?["invalid_time"] ??
              defaultErrorMessages["invalid_time"]!,
        ],
      });
    }

    if (date == null || time == null) {
      throw ValidationError({
        'invalid_date': [
          errorMessages?["invalid_date"] ??
              defaultErrorMessages["invalid_date"]!,
        ],
      });
    }

    final dateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
      time.second,
      time.millisecond,
      time.microsecond,
    );

    return dateTime as T;
  }
}
