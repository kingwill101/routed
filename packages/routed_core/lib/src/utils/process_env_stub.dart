/// Fallback when neither `dart:io` nor JS process is available.
Map<String, String> readProcessEnvironment() => const <String, String>{};

/// Whether the host reports Windows (unknown → false).
bool get hostIsWindows => false;
