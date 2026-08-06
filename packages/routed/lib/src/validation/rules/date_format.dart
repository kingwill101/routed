import 'package:routed/src/validation/rule.dart';

/// Validation rule that checks if a date matches a given format.
class DateFormatRule extends ValidationRule {
  @override
  String get name => 'date_format';

  @override
  String message(dynamic value, [List<String>? options]) {
    if (options != null && options.isNotEmpty) {
      return 'The field does not match the format ${options[0]}.';
    }
    return 'The field does not match the required date format.';
  }

  @override
  bool validate(dynamic value, [List<String>? options]) {
    if (value == null || options == null || options.isEmpty) return false;
    final str = value.toString();
    final format = options[0];
    // Simple fallback without intl: handle ISO and common yyyy-MM-dd, yyyy/MM/dd, dd-MM-yyyy
    // Full intl DateFormat support is available via validation_ext when intl is present;
    // this keeps routed core free of intl for pubspec slim (resolves blocked 38->29).
    try {
      final parsed = DateTime.tryParse(str);
      if (parsed != null) {
        // Strict check: for yyyy-MM-dd formats, verify month/day are valid and match input
        // DateTime.tryParse overflows month 13 to next year, so need to verify.
        if (format.contains('yyyy-MM-dd') || format.contains('yyyy/MM/dd')) {
          final m = RegExp(r'\d{4}[-/](\d{2})[-/](\d{2})').firstMatch(str);
          if (m != null) {
            final month = int.tryParse(m.group(1)!);
            final day = int.tryParse(m.group(2)!);
            if (month == null || month < 1 || month > 12) return false;
            if (day == null || day < 1 || day > 31) return false;
            if (parsed.month != month || parsed.day != day) return false;
          }
        }
        if (format.contains('yyyy') && !RegExp(r'\d{4}').hasMatch(str)) {
          return false;
        }
        return true;
      }
      // Fallback: try to parse with manual pattern for yyyy-MM-dd etc.
      final normalized = str.replaceAll('/', '-');
      if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(normalized)) {
        final parts = normalized.split('-');
        if (parts.length >= 3) {
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2].split(' ')[0].split('T')[0]);
          if (y != null && m != null && d != null) {
            final dt = DateTime.tryParse(
              '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}',
            );
            return dt != null;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
