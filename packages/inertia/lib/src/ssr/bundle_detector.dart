library;

import 'dart:io';

/// Detects the SSR bundle path from configured candidates.
///
/// ```dart
/// final detector = SsrBundleDetector(candidates: ['build/ssr.mjs']);
/// final bundle = detector.detect();
/// ```
class SsrBundleDetector {
  /// Creates a bundle detector.
  const SsrBundleDetector({
    this.bundle,
    this.workingDirectory,
    this.candidates = const [],
  });

  /// The explicit bundle path, if provided.
  final String? bundle;

  /// The directory used to resolve relative paths.
  final Directory? workingDirectory;

  /// Additional candidate bundle paths.
  final List<String> candidates;

  /// Returns the first existing bundle path, or `null` if none exist.
  String? detect() {
    final root = workingDirectory ?? Directory.current;
    final searchPaths = <String?>[
      bundle,
      ...candidates,
      _join(root, 'bootstrap/ssr/ssr.mjs'),
      _join(root, 'bootstrap/ssr/ssr.js'),
      _join(root, 'public/js/ssr.js'),
      _join(root, 'public/js/ssr.mjs'),
    ];

    for (final candidate in searchPaths) {
      if (candidate == null) continue;
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  /// Joins [root] and [path] into a file path.
  String _join(Directory root, String path) {
    return root.uri.resolve(path).toFilePath();
  }
}
