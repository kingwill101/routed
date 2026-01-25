library;

import 'inertia_headers.dart';

/// Parses Inertia-specific request headers into strongly typed values.
///
/// This utility is used by [InertiaRequest] and [PropertyContext] to interpret
/// partial reload, merge, and version metadata.
///
/// ```dart
/// final isInertia = InertiaHeaderUtils.isInertiaRequest(headers);
/// final partial = InertiaHeaderUtils.getPartialData(headers) ?? const [];
/// ```
class InertiaHeaderUtils {
  /// Returns `true` if [headers] mark this as an Inertia request.
  static bool isInertiaRequest(Map<String, String> headers) {
    return headers[InertiaHeaders.inertia] == 'true';
  }

  /// Returns the asset version if the header is present.
  static String? getVersion(Map<String, String> headers) {
    return headers[InertiaHeaders.inertiaVersion];
  }

  /// Parses the partial data header into a trimmed list of prop keys.
  ///
  /// Returns `null` when the header is missing or empty.
  static List<String>? getPartialData(Map<String, String> headers) {
    final data = headers[InertiaHeaders.inertiaPartialData];
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
    final data = headers[InertiaHeaders.inertiaPartialExcept];
    if (data == null) return null;

    return data
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Returns the partial component header value, if present.
  static String? getPartialComponent(Map<String, String> headers) {
    return headers[InertiaHeaders.inertiaPartialComponent];
  }

  /// Returns the trimmed error bag name, if present and non-empty.
  static String? getErrorBag(Map<String, String> headers) {
    final value = headers[InertiaHeaders.inertiaErrorBag];
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  /// Parses the reset header into a trimmed list of prop keys.
  ///
  /// Returns `null` when the header is missing or empty.
  static List<String>? getResetKeys(Map<String, String> headers) {
    final data = headers[InertiaHeaders.inertiaReset];
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
    final data = headers[InertiaHeaders.inertiaExceptOnceProps];
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
    final value = headers[InertiaHeaders.inertiaInfiniteScrollMergeIntent];
    if (value == null || value.trim().isEmpty) return null;
    return value.trim().toLowerCase();
  }

  /// Returns `true` when [headers] indicate a partial reload request.
  static bool isPartialReload(Map<String, String> headers) {
    return getPartialData(headers) != null || getPartialExcept(headers) != null;
  }
}
