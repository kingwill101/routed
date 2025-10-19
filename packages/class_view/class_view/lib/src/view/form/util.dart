import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

/// Convert a field name to a more readable format.
/// For example, converts 'first_name' to 'First name'.
String prettyName(String name) {
  if (name.isEmpty) return '';
  return name
      .replaceAll('_', ' ')
      .trim()
      .split(' ')
      .map(
        (word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1),
      )
      .join(' ');
}

/// HTML escape a string
String htmlEscape(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}

/// Convert a dictionary of attributes to a single string.
/// The returned string will contain a leading space followed by key="value",
/// XML-style pairs. In the case of a boolean value, the key will appear
/// without a value. It is assumed that the keys do not need to be
/// XML-escaped. If the passed dictionary is empty, then return an empty
/// string.
String flatAttrs(Map<String, dynamic> attrs) {
  final keyValueAttrs = <MapEntry<String, String>>[];
  final booleanAttrs = <String>[];

  for (final entry
      in attrs.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    if (entry.value is bool) {
      if (entry.value == true) {
        booleanAttrs.add(entry.key);
      }
    } else if (entry.value != null) {
      keyValueAttrs.add(
        MapEntry(entry.key, htmlEscape(entry.value.toString())),
      );
    }
  }

  final keyValueStr = keyValueAttrs
      .map((e) => ' ${e.key}="${e.value}"')
      .join('');

  final booleanStr = booleanAttrs.map((attr) => ' $attr').join('');

  return keyValueStr + booleanStr;
}

/// A collection of errors that knows how to display itself in various formats.
class ErrorDict {
  final Map<String, ErrorList> _errors = {};
  final String errorClass;

  ErrorDict({this.errorClass = 'errorlist'});

  void add(String field, String error) {
    _errors
        .putIfAbsent(field, () => ErrorList(errorClass: errorClass))
        .add(error);
  }

  Map<String, List<String>> asData() {
    return Map.fromEntries(
      _errors.entries.map((e) => MapEntry(e.key, e.value.asData())),
    );
  }

  String asJson({bool escapeHtml = false}) {
    return jsonEncode(getJsonData(escapeHtml: escapeHtml));
  }

  Map<String, List<Map<String, String>>> getJsonData({
    bool escapeHtml = false,
  }) {
    return Map.fromEntries(
      _errors.entries.map(
        (e) => MapEntry(e.key, e.value.getJsonData(escapeHtml: escapeHtml)),
      ),
    );
  }

  String asUl() {
    if (_errors.isEmpty) return '';

    final buffer = StringBuffer('<ul class="$errorClass">');
    for (final entry in _errors.entries) {
      buffer.write('<li>${entry.key}: ${entry.value.asUl()}</li>');
    }
    buffer.write('</ul>');
    return buffer.toString();
  }

  bool get isEmpty => _errors.isEmpty;

  bool get isNotEmpty => _errors.isNotEmpty;

  ErrorList? operator [](String key) => _errors[key];

  void operator []=(String key, ErrorList value) => _errors[key] = value;
}

/// A collection of errors that knows how to display itself in various formats.
class ErrorList {
  final List<String> _errors = [];
  final String errorClass;
  final String? fieldId;

  ErrorList({this.errorClass = 'errorlist', this.fieldId});

  void add(String error) => _errors.add(error);

  List<String> asData() => List.from(_errors);

  String asJson({bool escapeHtml = false}) {
    return jsonEncode(getJsonData(escapeHtml: escapeHtml));
  }

  List<Map<String, String>> getJsonData({bool escapeHtml = false}) {
    return _errors.map((error) {
      final message = escapeHtml ? htmlEscape(error) : error;
      return {'message': message, 'code': ''};
    }).toList();
  }

  String asUl() {
    if (_errors.isEmpty) return '';

    final idAttr = fieldId != null ? ' id="$fieldId"' : '';
    final buffer = StringBuffer('<ul class="$errorClass"$idAttr>');
    for (final error in _errors) {
      buffer.write('<li>${htmlEscape(error)}</li>');
    }
    buffer.write('</ul>');
    return buffer.toString();
  }

  bool get isEmpty => _errors.isEmpty;

  bool get isNotEmpty => _errors.isNotEmpty;

  int get length => _errors.length;

  String operator [](int index) => _errors[index];

  void operator []=(int index, String value) => _errors[index] = value;
}

/// When time zone support is enabled, convert naive datetimes
/// entered in the current time zone to aware datetimes.
DateTime? fromCurrentTimezone(DateTime? value) {
  if (value == null) return null;

  try {
    final location = tz.local;
    return tz.TZDateTime.from(value, location);
  } catch (e) {
    throw FormatException(
      'DateTime $value could not be interpreted in timezone ${tz.local}; '
      'it may be ambiguous or it may not exist.',
    );
  }
}

/// When time zone support is enabled, convert aware datetimes
/// to naive datetimes in the current time zone for display.
DateTime? toCurrentTimezone(DateTime? value) {
  if (value == null) return null;

  if (value is tz.TZDateTime) {
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }
  return value;
}
