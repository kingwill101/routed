import 'dart:io' show Platform;

/// Process environment via `dart:io` [Platform.environment].
Map<String, String> readProcessEnvironment() {
  try {
    return Map<String, String>.from(Platform.environment);
  } catch (_) {
    // Some embedders expose dart:io but leave environment unsupported.
    return const <String, String>{};
  }
}

/// Whether this host reports a Windows operating system.
bool get hostIsWindows {
  try {
    return Platform.isWindows;
  } catch (_) {
    return false;
  }
}
