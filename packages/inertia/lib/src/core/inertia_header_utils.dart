library;

import 'inertia_headers.dart';

/// Parses Inertia-specific request headers into strongly typed values.
///
/// This utility is used by [InertiaRequest] and [PropertyContext] to interpret
/// partial reload, merge, and version metadata.
///
/// Header lookups are case-insensitive, so maps with lowercased keys
/// (e.g. from `dart:io` [HttpHeaders]) work correctly.
///
/// ```dart
/// final isInertia = InertiaHeaderUtils.isInertiaRequest(headers);
/// final partial = InertiaHeaderUtils.getPartialData(headers) ?? const [];
/// ```
class InertiaHeaderUtils {
  /// Case-insensitive header lookup.
  ///
  /// HTTP header names are case-insensitive per RFC 7230, but Dart maps are
  /// case-sensitive by default. This helper tries the exact key first, then
  /// falls back to a linear scan with case-insensitive comparison.
  static String? _get(Map<String, String> headers, String key) {
    // Fast path: exact match (works when the map already uses matching case).
    final exact = headers[key];
    if (exact != null) return exact;

    // Slow path: case-insensitive scan.
    final lowerKey = key.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lowerKey) return entry.value;
    }
    return null;
  }

  /// Returns `true` if [headers] mark this as an Inertia request.
  static bool isInertiaRequest(Map<String, String> headers) {
    return _get(headers, InertiaHeaders.inertia) == 'true';
  }

  /// Returns the asset version if the header is present.
  static String? getVersion(Map<String, String> headers) {
    return _get(headers, InertiaHeaders.inertiaVersion);
  }

  /// Parses the partial data header into a trimmed list of prop keys.
  ///
  /// Returns `null` when the header is missing or empty.
  static List<String>? getPartialData(Map<String, String> headers) {
    final data = _get(headers, InertiaHeaders.inertiaPartialData);
    if (data == null) return null;

    return data
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Parses the partial-except header into a trimmed list of prop keys.
  ///
  /// Returns `null` when the header is missing or empty.
  static List<String>? getPartialExcept(Map<String, String> headers) {
    final data = _get(headers, InertiaHeaders.inertiaPartialExcept);
    if (data == null) return null;

    return data
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Returns the partial component header value, if present.
  static String? getPartialComponent(Map<String, String> headers) {
    return _get(headers, InertiaHeaders.inertiaPartialComponent);
  }

  /// Returns the trimmed error bag name, if present and non-empty.
  static String? getErrorBag(Map<String, String> headers) {
    final value = _get(headers, InertiaHeaders.inertiaErrorBag);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// Parses the reset header into a trimmed list of prop keys.
  ///
  /// Returns `null` when the header is missing or empty.
  static List<String>? getResetKeys(Map<String, String> headers) {
    final data = _get(headers, InertiaHeaders.inertiaReset);
    if (data == null) return null;

    return data
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Parses the except-once header into a trimmed list of prop keys.
  ///
  /// Returns `null` when the header is missing or empty.
  static List<String>? getExceptOnceProps(Map<String, String> headers) {
    final data = _get(headers, InertiaHeaders.inertiaExceptOnceProps);
    if (data == null) return null;

    return data
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Returns the normalized merge intent string, if present.
  ///
  /// The value is trimmed and lowercased to simplify comparisons.
  static String? getMergeIntent(Map<String, String> headers) {
    final value = _get(
      headers,
      InertiaHeaders.inertiaInfiniteScrollMergeIntent,
    );
    if (value == null || value.trim().isEmpty) return null;
    return value.trim().toLowerCase();
  }

  /// Returns `true` when [headers] indicate a partial reload request.
  static bool isPartialReload(Map<String, String> headers) {
    return getPartialData(headers) != null || getPartialExcept(headers) != null;
  }
}
