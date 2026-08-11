import 'dart:convert';

/// Escapes HTML special characters in the given string
String escapeHtml(String text) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(text);

/// Marks a string as safe for HTML rendering
/// This is used to indicate that the string has already been properly escaped
/// and should not be escaped again
class SafeString {
  final String value;

  const SafeString(this.value);

  @override
  String toString() => value;

  /// Creates a SafeString from a String
  static SafeString fromString(String value) => SafeString(value);
}

/// Marks a string as safe for HTML rendering
SafeString markSafe(String html) => SafeString(html);

/// Checks if a string is marked as safe
bool isSafe(dynamic value) => value is SafeString;
