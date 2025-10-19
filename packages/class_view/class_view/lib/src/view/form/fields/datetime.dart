import 'package:intl/intl.dart';

import '../validation.dart';
import 'temporal.dart';

/// A form field that handles DateTime input.
/// This field can accept:
/// - DateTime objects
/// - Strings in ISO format (e.g. "2006-10-25 14:30:45")
/// - Strings in US format (e.g. "10/25/2006 14:30:45")
/// - Strings with custom formats specified in inputFormats
class DateTimeField extends BaseTemporalField<DateTime> {
  /// Creates a new DateTimeField.
  DateTimeField({
    super.required = false,
    super.label,
    super.initial,
    super.helpText,
    List<String>? inputFormats,
    super.errorMessages,
  }) : super(
         inputFormats:
             inputFormats ??
             [
               'yyyy-MM-dd HH:mm:ss.SSSSSS',
               'yyyy-MM-dd HH:mm:ss.SSSS',
               'yyyy-MM-dd HH:mm:ss',
               'yyyy-MM-dd HH:mm',
               'yyyy-MM-dd',
               'MM/dd/yyyy HH:mm:ss.SSSSSS',
               'MM/dd/yyyy HH:mm:ss',
               'MM/dd/yyyy HH:mm',
               'MM/dd/yyyy',
               'MM/dd/yy HH:mm:ss.SSSSSS',
               'MM/dd/yy HH:mm:ss',
               'MM/dd/yy HH:mm',
               'MM/dd/yy',
               "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
               "yyyy-MM-dd'T'HH:mm:ss",
               "yyyy-MM-dd'T'HH:mm",
               "yyyy-MM-dd'T'HH:mmZ",
               "yyyy-MM-dd'T'HH:mm+HH:mm",
             ],
       );

  @override
  DateTime? toDart(dynamic value) {
    // Handle null and empty strings
    if (value == null || (value is String && value.trim().isEmpty)) {
      if (required) {
        throw ValidationError({
          'required': [errorMessages?['required'] ?? 'This field is required.'],
        });
      }
      return null;
    }

    if (value is String) {
      String stringValue = value.trim();

      // Reject 12-hour time formats (a.m., p.m., AM, PM)
      final lowerValue = stringValue.toLowerCase();
      if (lowerValue.contains('a.m.') ||
          lowerValue.contains('p.m.') ||
          lowerValue.contains('am') ||
          lowerValue.contains('pm')) {
        throw ValidationError({
          'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
        });
      }

      // Pre-validate the input format
      if (stringValue.contains(':')) {
        final hourMatch = RegExp(r'(\d{1,2})(?=:)').firstMatch(stringValue);
        if (hourMatch != null) {
          final hour = int.parse(hourMatch.group(1)!);
          if (hour >= 24) {
            throw ValidationError({
              'invalid': [
                errorMessages?['invalid'] ?? 'Enter a valid date/time.',
              ],
            });
          }
        }

        final minuteMatch = RegExp(
          r':(\d{1,2})(?=:|$|\s|Z)',
        ).firstMatch(stringValue);
        if (minuteMatch != null) {
          final minute = int.parse(minuteMatch.group(1)!);
          if (minute >= 60) {
            throw ValidationError({
              'invalid': [
                errorMessages?['invalid'] ?? 'Enter a valid date/time.',
              ],
            });
          }
        }

        final secondMatch = RegExp(
          r':(\d{1,2})(?=\.|$|\s|Z)',
        ).firstMatch(stringValue);
        if (secondMatch != null) {
          final second = int.parse(secondMatch.group(1)!);
          if (second >= 60) {
            throw ValidationError({
              'invalid': [
                errorMessages?['invalid'] ?? 'Enter a valid date/time.',
              ],
            });
          }
        }
      }

      final monthMatch = RegExp(
        r'(?<=-|/)(\d{1,2})(?=-|/)',
      ).firstMatch(stringValue);
      if (monthMatch != null) {
        final month = int.parse(monthMatch.group(1)!);
        if (month < 1 || month > 12) {
          throw ValidationError({
            'invalid': [
              errorMessages?['invalid'] ?? 'Enter a valid date/time.',
            ],
          });
        }
      }

      final dayMatch = RegExp(
        r'(?<=-|/)(\d{1,2})(?=\s|$|T)',
      ).firstMatch(stringValue);
      if (dayMatch != null) {
        final day = int.parse(dayMatch.group(1)!);
        if (day < 1 || day > 31) {
          throw ValidationError({
            'invalid': [
              errorMessages?['invalid'] ?? 'Enter a valid date/time.',
            ],
          });
        }
      }

      // If custom formats are provided, only use those
      if (inputFormats.isNotEmpty) {
        ValidationError? lastError;
        for (final format in inputFormats) {
          try {
            return strptime(stringValue, format);
          } catch (e) {
            lastError = e is ValidationError
                ? e
                : ValidationError({
                    'invalid': [
                      errorMessages?['invalid'] ?? 'Enter a valid date/time.',
                    ],
                  });
            // Continue to next format
          }
        }
        // If we reach here with custom formats, none of them worked
        throw lastError ??
            ValidationError({
              'invalid': [
                errorMessages?['invalid'] ?? 'Enter a valid date/time.',
              ],
            });
      }

      // Try built-in formats
      ValidationError? lastError;

      // First try to parse with DateTime.parse for ISO formats with timezone
      if (stringValue.contains('T') || stringValue.endsWith('Z')) {
        try {
          // For Z-suffixed times without T, add T to make it proper ISO format
          if (stringValue.endsWith('Z') && !stringValue.contains('T')) {
            final parts = stringValue.split(' ');
            if (parts.length == 2) {
              stringValue = '${parts[0]}T${parts[1]}';
            }
          }

          final dt = DateTime.parse(stringValue);
          _validateDateComponents(dt);
          return dt.toUtc(); // Ensure we return UTC
        } catch (e) {
          // If parsing fails, continue to other formats
          lastError = e is ValidationError
              ? e
              : ValidationError({
                  'invalid': [
                    errorMessages?['invalid'] ?? 'Enter a valid date/time.',
                  ],
                });
        }
      }

      // Try each default format
      for (final format in [
        'yyyy-MM-dd HH:mm:ss.SSSSSS',
        'yyyy-MM-dd HH:mm:ss.SSSS',
        'yyyy-MM-dd HH:mm:ss',
        'yyyy-MM-dd HH:mm',
        'yyyy-MM-dd',
        'MM/dd/yyyy HH:mm:ss.SSSSSS',
        'MM/dd/yyyy HH:mm:ss',
        'MM/dd/yyyy HH:mm',
        'MM/dd/yyyy',
        'MM/dd/yy HH:mm:ss.SSSSSS',
        'MM/dd/yy HH:mm:ss',
        'MM/dd/yy HH:mm',
        'MM/dd/yy',
      ]) {
        try {
          return strptime(stringValue, format);
        } catch (e) {
          lastError = e is ValidationError
              ? e
              : ValidationError({
                  'invalid': [
                    errorMessages?['invalid'] ?? 'Enter a valid date/time.',
                  ],
                });
          // Continue to next format
        }
      }

      // If we reach here, no format worked
      throw lastError ??
          ValidationError({
            'invalid': [
              errorMessages?['invalid'] ?? 'Enter a valid date/time.',
            ],
          });
    }

    if (value is DateTime) {
      _validateDateComponents(value);
      return DateTime.utc(
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
        value.second,
        value.millisecond * 1000,
        value.microsecond,
      );
    }

    throw ValidationError({
      'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
    });
  }

  @override
  DateTime strptime(String value, String format) {
    try {
      final formatter = DateFormat(format);
      DateTime date;
      try {
        date = formatter.parse(value);
      } catch (e) {
        throw ValidationError({
          'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
        });
      }

      // Additional validation for days in month
      final daysInMonth = DateTime(date.year, date.month + 1, 0).day;
      if (date.day > daysInMonth) {
        throw ValidationError({
          'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
        });
      }

      // Ensure the input string matches the format exactly
      final reformatted = formatter.format(date);
      if (reformatted != value) {
        throw ValidationError({
          'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
        });
      }

      return DateTime.utc(
        date.year,
        date.month,
        date.day,
        date.hour,
        date.minute,
        date.second,
        date.millisecond * 1000,
        date.microsecond,
      );
    } catch (e) {
      if (e is ValidationError) rethrow;
      throw ValidationError({
        'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
      });
    }
  }

  void _validateDateComponents(DateTime date) {
    if (date.month < 1 ||
        date.month > 12 ||
        date.day < 1 ||
        date.day > 31 ||
        date.hour < 0 ||
        date.hour >= 24 ||
        date.minute < 0 ||
        date.minute >= 60 ||
        date.second < 0 ||
        date.second >= 60) {
      throw ValidationError({
        'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
      });
    }

    // Additional validation for days in month
    final daysInMonth = DateTime(date.year, date.month + 1, 0).day;
    if (date.day > daysInMonth) {
      throw ValidationError({
        'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
      });
    }
  }

  // ignore: unused_element
  DateTime _parseISOFormat(String value) {
    try {
      // Handle ISO 8601 format with timezone
      if (value.contains('T')) {
        if (value.endsWith('Z')) {
          // Already in UTC
          final dt = DateTime.parse(value);
          _validateDateComponents(dt);
          return dt;
        } else if (value.contains('+')) {
          // Convert to UTC by subtracting the offset
          final parts = value.split('+');
          final dt = DateTime.parse('${parts[0]}Z');
          _validateDateComponents(dt);
          final offset = parts[1].split(':');
          final hours = int.parse(offset[0]);
          final minutes = offset.length > 1 ? int.parse(offset[1]) : 0;
          if (hours >= 24 || minutes >= 60) {
            throw ValidationError({
              'invalid': [
                errorMessages?['invalid'] ?? 'Enter a valid date/time.',
              ],
            });
          }
          return dt.subtract(Duration(hours: hours, minutes: minutes));
        } else if (value.contains('-') && value.split('T')[1].contains('-')) {
          // Handle negative timezone offset
          final mainParts = value.split('T');
          final timeParts = mainParts[1].split('-');
          if (timeParts.length > 1) {
            final dt = DateTime.parse('${mainParts[0]}T${timeParts[0]}Z');
            _validateDateComponents(dt);
            final offset = timeParts[1].split(':');
            final hours = int.parse(offset[0]);
            final minutes = offset.length > 1 ? int.parse(offset[1]) : 0;
            if (hours >= 24 || minutes >= 60) {
              throw ValidationError({
                'invalid': [
                  errorMessages?['invalid'] ?? 'Enter a valid date/time.',
                ],
              });
            }
            return dt.add(Duration(hours: hours, minutes: minutes));
          }
        }
      }

      // Parse the date and time parts
      final parts = value.split(' ');
      final datePart = parts[0].replaceAll('T', ' ').trim();
      String? timePart = parts.length > 1 ? parts[1].trim() : null;

      // Parse date
      final dateParts = datePart.split('-');
      if (dateParts.length != 3) {
        throw const FormatException('Invalid date format');
      }

      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      // Validate date components
      if (month < 1 || month > 12 || day < 1) {
        throw ValidationError({
          'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
        });
      }

      // Validate days in month
      final daysInMonth = DateTime(year, month + 1, 0).day;
      if (day > daysInMonth) {
        throw ValidationError({
          'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
        });
      }

      // If no time provided, return midnight UTC
      if (timePart == null) {
        return DateTime.utc(year, month, day);
      }

      // Parse time
      final timeParts = timePart.split(':');
      if (timeParts.length < 2) {
        throw const FormatException('Invalid time format');
      }

      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      // Validate time components
      if (hour < 0 || hour >= 24 || minute < 0 || minute >= 60) {
        throw ValidationError({
          'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
        });
      }

      int second = 0;
      int microsecond = 0;

      if (timeParts.length > 2) {
        final secondParts = timeParts[2].split('.');
        second = int.parse(secondParts[0]);
        if (second < 0 || second >= 60) {
          throw ValidationError({
            'invalid': [
              errorMessages?['invalid'] ?? 'Enter a valid date/time.',
            ],
          });
        }
        if (secondParts.length > 1) {
          final microStr = secondParts[1].padRight(6, '0').substring(0, 6);
          microsecond = int.parse(microStr);
        }
      }

      return DateTime.utc(
        year,
        month,
        day,
        hour,
        minute,
        second,
        0,
        microsecond,
      );
    } catch (e) {
      if (e is ValidationError) rethrow;
      throw ValidationError({
        'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
      });
    }
  }

  // ignore: unused_element
  DateTime _parseUSFormat(String value) {
    try {
      final parts = value.split(' ');
      final datePart = parts[0].trim();
      String? timePart = parts.length > 1 ? parts[1].trim() : null;

      // Parse date
      final dateParts = datePart.split('/');
      if (dateParts.length != 3) {
        throw const FormatException('Invalid date format');
      }

      final month = int.parse(dateParts[0]);
      final day = int.parse(dateParts[1]);
      var year = int.parse(dateParts[2]);

      // Handle two-digit years
      if (year < 100) {
        year += year < 50 ? 2000 : 1900;
      }

      // If no time provided, return midnight UTC
      if (timePart == null) {
        return DateTime.utc(year, month, day);
      }

      // Parse time
      final timeParts = timePart.split(':');
      if (timeParts.length < 2) {
        throw const FormatException('Invalid time format');
      }

      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      int second = 0;
      int microsecond = 0;

      if (timeParts.length > 2) {
        final secondParts = timeParts[2].split('.');
        second = int.parse(secondParts[0]);
        if (secondParts.length > 1) {
          final microStr = secondParts[1].padRight(6, '0').substring(0, 6);
          microsecond = int.parse(microStr);
        }
      }

      return DateTime.utc(
        year,
        month,
        day,
        hour,
        minute,
        second,
        0,
        microsecond,
      );
    } catch (e) {
      throw ValidationError({
        'invalid': [errorMessages?['invalid'] ?? 'Enter a valid date/time.'],
      });
    }
  }

  @override
  bool hasChanged(dynamic initial, dynamic data) {
    // Convert initial to typed value
    DateTime? dartInitial;
    try {
      dartInitial = initial is DateTime ? initial : toDart(initial);
    } catch (_) {
      dartInitial = null;
    }

    if (dartInitial == null &&
        (data == null || (data is String && data.trim().isEmpty))) {
      return false;
    }

    try {
      final dataDate = toDart(data);
      if (dartInitial == null) return dataDate != null;
      if (dataDate == null) return true;

      final normalizedInitial = DateTime.utc(
        dartInitial.year,
        dartInitial.month,
        dartInitial.day,
        dartInitial.hour,
        dartInitial.minute,
        dartInitial.second,
        dartInitial.millisecond * 1000,
        dartInitial.microsecond,
      );
      final normalizedData = DateTime.utc(
        dataDate.year,
        dataDate.month,
        dataDate.day,
        dataDate.hour,
        dataDate.minute,
        dataDate.second,
        dataDate.millisecond * 1000,
        dataDate.microsecond,
      );

      return normalizedInitial.microsecondsSinceEpoch !=
          normalizedData.microsecondsSinceEpoch;
    } catch (_) {
      return true;
    }
  }
}
