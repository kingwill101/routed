library;

/// Configuration values used by Inertia testing helpers.
class InertiaTestingSettings {
  /// Creates testing settings for Inertia assertions.
  InertiaTestingSettings({
    this.ensurePagesExist = false,
    List<String>? pagePaths,
    List<String>? pageExtensions,
  }) : pagePaths = pagePaths ?? const [],
       pageExtensions =
           pageExtensions ?? const ['js', 'jsx', 'ts', 'tsx', 'vue', 'svelte'];

  /// Whether component file existence checks are enabled.
  bool ensurePagesExist;

  /// Base paths used to resolve component files.
  List<String> pagePaths;

  /// Allowed file extensions for component files.
  List<String> pageExtensions;
}
