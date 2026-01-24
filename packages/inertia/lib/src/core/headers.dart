/// Inertia protocol header constants and utilities
library;

/// Inertia.js protocol headers
class InertiaHeaders {
  static const String inertia = 'X-Inertia';
  static const String inertiaVersion = 'X-Inertia-Version';
  static const String inertiaPartialData = 'X-Inertia-Partial-Data';
  static const String inertiaPartialComponent = 'X-Inertia-Partial-Component';
  static const String inertiaLocation = 'X-Inertia-Location';
  static const String inertiaReset = 'X-Inertia-Reset';
  static const String inertiaVary = 'Vary';
}

/// Header utilities for detecting Inertia requests
class InertiaHeaderUtils {
  /// Check if request is an Inertia request
  static bool isInertiaRequest(Map<String, String> headers) {
    return headers[InertiaHeaders.inertia]?.toLowerCase() == 'true';
  }

  /// Extract Inertia version from headers
  static String? getVersion(Map<String, String> headers) {
    return headers[InertiaHeaders.inertiaVersion];
  }

  /// Extract partial data header
  static List<String>? getPartialData(Map<String, String> headers) {
    final data = headers[InertiaHeaders.inertiaPartialData];
    if (data == null) return null;

    return data
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Extract partial component header
  static String? getPartialComponent(Map<String, String> headers) {
    return headers[InertiaHeaders.inertiaPartialComponent];
  }

  /// Extract reset keys header
  static List<String>? getResetKeys(Map<String, String> headers) {
    final data = headers[InertiaHeaders.inertiaReset];
    if (data == null) return null;

    return data
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Check if request is a partial reload
  static bool isPartialReload(Map<String, String> headers) {
    return getPartialData(headers) != null;
  }
}
