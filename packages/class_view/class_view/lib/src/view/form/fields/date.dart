import 'package:intl/intl.dart';

import '../validation.dart' show ValidationError;
import '../widgets/text_input.dart';
import 'temporal.dart';

/// A form field that validates and converts date input.
///
/// This field can handle various date formats and converts them to DateTime objects.
/// It supports both string input in various formats and DateTime objects directly.
class DateField extends BaseTemporalField<DateTime> {
  static final _monthNames = {
    'jan': 1,
    'january': 1,
    'feb': 2,
    'february': 2,
    'mar': 3,
    'march': 3,
    'apr': 4,
    'april': 4,
    'may': 5,
    'jun': 6,
    'june': 6,
    'jul': 7,
    'july': 7,
    'aug': 8,
    'august': 8,
    'sep': 9,
    'september': 9,
    'oct': 10,
    'october': 10,
    'nov': 11,
    'november': 11,
    'dec': 12,
    'december': 12,
  };

  /// Default error messages for this field type
  @override
  Map<String, String> get defaultErrorMessages => {
    'required': 'This field is required.',
    'invalid': 'Enter a valid date.',
  };

  /// Creates a new [DateField].
  ///
  /// The [inputFormats] parameter specifies the date formats to try when parsing
  /// input strings. If not provided, defaults to common US date formats.
  DateField({
    super.name,
    super.required,
    super.initial,
    super.label,
    super.helpText,
    super.errorMessages,
    super.showHiddenInitial,
    super.disabled,
    super.labelSuffix,
    super.localize = true,
    super.templateName,
    List<String>? inputFormats,
  }) : super(
         inputFormats:
             inputFormats ??
             [
               'yyyy-MM-dd',
               'M/d/yyyy',
               'M/d/yy',
               'MMM d yyyy',
               'MMMM d yyyy',
               'MMMM d, yyyy',
               'd MMMM yyyy',
               'd MMMM, yyyy',
             ],
         widget: TextInput(),
       );

  DateTime _normalizeDate(DateTime date) {
    // Normalize to midnight UTC
    return DateTime.utc(date.year, date.month, date.day);
  }

  int _normalizeYear(int year) {
    // Handle two-digit years
    if (year < 100) {
      return year + (year < 70 ? 2000 : 1900);
    }
    return year;
  }

  bool _isValidDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return false;
    }
    try {
      final date = DateTime.utc(year, month, day);
      return date.year == year && date.month == month && date.day == day;
    } catch (_) {
      return false;
    }
  }

  // ignore: unused_element
  DateTime? _parseISOFormat(String value) {
    final regex = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
    final match = regex.firstMatch(value);
    if (match != null) {
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      if (_isValidDate(year, month, day)) {
        return DateTime.utc(year, month, day);
      }
    }
    return null;
  }

  // ignore: unused_element
  DateTime? _parseUSFormat(String value, bool twoDigitYear) {
    final regex = twoDigitYear
        ? RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2})$')
        : RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');

    final match = regex.firstMatch(value);
    if (match != null) {
      final month = int.parse(match.group(1)!);
      final day = int.parse(match.group(2)!);
      var year = int.parse(match.group(3)!);

      if (twoDigitYear) {
        year = _normalizeYear(year);
      }

      if (_isValidDate(year, month, day)) {
        return DateTime.utc(year, month, day);
      }
    }
    return null;
  }

  // ignore: unused_element
  DateTime? _parseMonthNameFormat(String value, bool dayFirst) {
    value = value
        .toLowerCase()
        .replaceAll(',', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    for (final entry in _monthNames.entries) {
      final monthName = entry.key;
      final monthNum = entry.value;

      // More flexible regex patterns to handle additional spaces
      final pattern = dayFirst
          ? RegExp(
              r'^(\d{1,2})\s+(' + monthName + r')\s+(\d{4})$',
              caseSensitive: false,
            )
          : RegExp(
              r'^(' + monthName + r')\s+(\d{1,2})\s+(\d{4})$',
              caseSensitive: false,
            );

      final match = pattern.firstMatch(value);
      if (match != null) {
        final year = int.parse(dayFirst ? match.group(3)! : match.group(3)!);
        final day = int.parse(dayFirst ? match.group(1)! : match.group(2)!);

        if (_isValidDate(year, monthNum, day)) {
          return DateTime.utc(year, monthNum, day);
        }
      }
    }
    return null;
  }

  // ignore: unused_element
  DateTime? _parseCustomFormat(String value, String format) {
    try {
      // Create a regex pattern based on the format
      var pattern = format
          .replaceAll('yyyy', r'(\d{4})')
          .replaceAll('MM', r'(\d{2})')
          .replaceAll('dd', r'(\d{2})')
          .replaceAll(' ', r'\s+');
      pattern = '^$pattern\$';

      final regex = RegExp(pattern);
      final match = regex.firstMatch(value);

      if (match != null) {
        final parts = format.split(' ');
        final values = value.split(RegExp(r'\s+'));

        int? year;
        int? month;
        int? day;

        for (var i = 0; i < parts.length; i++) {
          final formatPart = parts[i];
          final valuePart = values[i];

          if (formatPart == 'yyyy') {
            year = int.parse(valuePart);
          } else if (formatPart == 'MM') {
            month = int.parse(valuePart);
          } else if (formatPart == 'dd') {
            day = int.parse(valuePart);
          }
        }

        if (year != null && month != null && day != null) {
          if (_isValidDate(year, month, day)) {
            return DateTime.utc(year, month, day);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  DateTime strptime(String value, String format) {
    try {
      // Handle two-digit year formats specifically
      if (format == 'M/d/yy') {
        final regex = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2})$');
        final match = regex.firstMatch(value);
        if (match != null) {
          final month = int.parse(match.group(1)!);
          final day = int.parse(match.group(2)!);
          var year = int.parse(match.group(3)!);
          year = _normalizeYear(year);

          return DateTime.utc(year, month, day);
        }
      }

      // Try to parse with DateFormat first
      try {
        final formatter = DateFormat(format);
        final date = formatter.parse(value);

        // Always normalize the year for all date formats when year is small
        if (date.year < 100) {
          return DateTime.utc(_normalizeYear(date.year), date.month, date.day);
        }

        return _normalizeDate(date);
      } catch (e) {
        // If DateFormat fails, try some custom parsing for specific formats
        if (format.contains('yy') && !format.contains('yyyy')) {
          // Try to extract parts from date string based on the format
          final parts = value.split('/');
          if (parts.length == 3 && parts[2].length == 2) {
            try {
              final month = int.parse(parts[0]);
              final day = int.parse(parts[1]);
              var year = int.parse(parts[2]);
              year = _normalizeYear(year);

              return DateTime.utc(year, month, day);
            } catch (_) {
              // Fall through to the error handling
            }
          }
        }

        // If all parsing attempts fail, throw the validation error
        throw ValidationError({
          'invalid': [
            errorMessages?['invalid'] ?? defaultErrorMessages['invalid']!,
          ],
        }, errorMessages?['invalid'] ?? defaultErrorMessages['invalid']!);
      }
    } catch (e) {
      if (e is ValidationError) {
        rethrow;
      }

      final message =
          errorMessages?['invalid'] ?? defaultErrorMessages['invalid']!;
      throw ValidationError({
        'invalid': [message],
      }, message);
    }
  }

  @override
  DateTime? toDart(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      if (required) {
        final message =
            errorMessages?['required'] ?? defaultErrorMessages['required']!;
        throw ValidationError({
          'required': [message],
        }, message);
      }
      return null;
    }

    if (value is DateTime) {
      return _normalizeDate(value);
    }

    final stringValue = value.toString().trim();

    // Custom handling for two-digit year formats (MM/DD/YY)
    final twoDigitRegex = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2})$');
    final match = twoDigitRegex.firstMatch(stringValue);
    if (match != null) {
      try {
        final month = int.parse(match.group(1)!);
        final day = int.parse(match.group(2)!);
        var year = int.parse(match.group(3)!);

        // Validate month is in range 1-12 before continuing
        if (month < 1 || month > 12) {
          throw ValidationError({
            'invalid': [
              errorMessages?['invalid'] ?? defaultErrorMessages['invalid']!,
            ],
          }, errorMessages?['invalid'] ?? defaultErrorMessages['invalid']!);
        }

        year = _normalizeYear(year);

        if (_isValidDate(year, month, day)) {
          return DateTime.utc(year, month, day);
        } else {
          throw ValidationError({
            'invalid': [
              errorMessages?['invalid'] ?? defaultErrorMessages['invalid']!,
            ],
          }, errorMessages?['invalid'] ?? defaultErrorMessages['invalid']!);
        }
      } catch (e) {
        if (e is ValidationError) {
          rethrow;
        }
        // Continue with other formats if this fails
      }
    }

    // Try each format in order
    for (final format in inputFormats) {
      try {
        return strptime(stringValue, format);
      } catch (e) {
        // Continue trying other formats
      }
    }

    // Couldn't parse with any format
    final message =
        errorMessages?['invalid'] ?? defaultErrorMessages['invalid']!;
    throw ValidationError({
      'invalid': [message],
    }, message);
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

      final normalizedInitial = _normalizeDate(dartInitial);
      final normalizedData = dataDate; // Already normalized by toDart

      return normalizedInitial != normalizedData;
    } catch (_) {
      return true;
    }
  }
}
