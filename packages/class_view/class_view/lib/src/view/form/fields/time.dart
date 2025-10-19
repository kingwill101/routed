import 'package:intl/intl.dart';

import '../validation.dart';
import '../widgets/base_widget.dart' show Widget;
import '../widgets/datetime/time_input.dart';
import '../widgets/hidden_input.dart';
import 'field.dart';

class TimeField<T> extends Field<T> {
  @override
  Map<String, String> get defaultErrorMessages => const {
    "required": "This field is required.",
    "invalid": "Enter a valid time.",
    "min_time": "Time must be %(min_time)s or later",
    "max_time": "Time must be %(max_time)s or earlier",
  };

  final DateTime? minTime;
  final DateTime? maxTime;
  final List<String> inputFormats;

  TimeField({
    String? name,
    this.minTime,
    this.maxTime,
    List<String>? inputFormats,
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
  }) : inputFormats =
           inputFormats ?? ['HH:mm', 'HH:mm:ss', 'h:mm a', 'h:mm:ss a'],
       super(
         name: name ?? '',
         widget: widget ?? TimeInput(),
         hiddenWidget: hiddenWidget ?? HiddenInput(),
         errorMessages: {
           ...const {
             "required": "This field is required.",
             "invalid": "Enter a valid time.",
             "min_time": "Time must be %(min_time)s or later",
             "max_time": "Time must be %(max_time)s or earlier",
           },
           ...?errorMessages,
         },
       );

  @override
  T? toDart(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return null;
    }

    String timeStr = value.toString().trim();

    // Try each format in order
    for (final format in inputFormats) {
      if (format.contains('a')) {
        // AM/PM format
        if (timeStr.toLowerCase().contains('am') ||
            timeStr.toLowerCase().contains('pm')) {
          try {
            final parts = timeStr.toLowerCase().split(' ');
            if (parts.length == 2) {
              final timeParts = parts[0].split(':');
              if (timeParts.length >= 2) {
                var hours = int.parse(timeParts[0]);
                final minutes = int.parse(timeParts[1]);
                final seconds = format.contains('ss') && timeParts.length > 2
                    ? int.parse(timeParts[2])
                    : 0;

                if (hours >= 1 &&
                    hours <= 12 &&
                    minutes >= 0 &&
                    minutes < 60 &&
                    seconds >= 0 &&
                    seconds < 60) {
                  if (parts[1] == 'pm' && hours != 12) {
                    hours += 12;
                  } else if (parts[1] == 'am' && hours == 12) {
                    hours = 0;
                  }
                  return DateTime(1970, 1, 1, hours, minutes, seconds) as T;
                }
              }
            }
          } catch (_) {
            continue;
          }
        }
      } else {
        // 24-hour format
        try {
          final parts = timeStr.split(':');
          if (parts.length >= 2) {
            final hours = int.parse(parts[0]);
            final minutes = int.parse(parts[1]);
            final seconds = format.contains('ss') && parts.length > 2
                ? int.parse(parts[2])
                : 0;

            // Only accept seconds if the format includes them
            if (!format.contains('ss') && parts.length > 2) {
              continue;
            }

            if (hours >= 0 &&
                hours < 24 &&
                minutes >= 0 &&
                minutes < 60 &&
                seconds >= 0 &&
                seconds < 60) {
              return DateTime(1970, 1, 1, hours, minutes, seconds) as T;
            }
          }
        } catch (_) {
          continue;
        }
      }
    }

    throw ValidationError({
      'invalid': [
        errorMessages?["invalid"] ?? defaultErrorMessages["invalid"]!,
      ],
    });
  }

  @override
  Future<void> validate(T? value) async {
    await super.validate(value);

    if (value == null || value.toString().isEmpty) {
      return;
    }

    final time = value as DateTime;
    if (minTime != null && time.isBefore(minTime!)) {
      throw ValidationError({
        'min_time': [
          (errorMessages?["min_time"] ?? defaultErrorMessages["min_time"]!)
              .replaceAll("%(min_time)s", _formatTime(minTime!)),
        ],
      });
    }

    if (maxTime != null && time.isAfter(maxTime!)) {
      throw ValidationError({
        'max_time': [
          (errorMessages?["max_time"] ?? defaultErrorMessages["max_time"]!)
              .replaceAll("%(max_time)s", _formatTime(maxTime!)),
        ],
      });
    }
  }

  String _formatTime(DateTime time) {
    return DateFormat('HH:mm:ss').format(time);
  }

  @override
  Map<String, dynamic> widgetAttrs(Widget widget) {
    final attrs = super.widgetAttrs(widget);
    if (widget is TimeInput) {
      if (minTime != null) {
        attrs["min"] = _formatTime(minTime!);
      }
      if (maxTime != null) {
        attrs["max"] = _formatTime(maxTime!);
      }
    }
    return attrs;
  }

  @override
  bool hasChanged(dynamic initial, dynamic data) {
    // Convert to typed values
    DateTime? dartInitial;
    DateTime? dartData;

    try {
      if (initial is DateTime) {
        dartInitial = initial;
      } else {
        dartInitial = toDart(initial) as DateTime?;
      }
    } catch (_) {
      dartInitial = null;
    }

    try {
      if (data is DateTime) {
        dartData = data;
      } else {
        dartData = toDart(data) as DateTime?;
      }
    } catch (_) {
      return true; // If conversion fails, consider it changed
    }

    if (dartInitial == null && dartData == null) {
      return false;
    }

    if (dartInitial == null || dartData == null) {
      return true;
    }

    return dartInitial.hour != dartData.hour ||
        dartInitial.minute != dartData.minute ||
        dartInitial.second != dartData.second;
  }
}
