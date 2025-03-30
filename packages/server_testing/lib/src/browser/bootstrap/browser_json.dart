/// Represents the structure of the `browsers.json` configuration file,
/// typically used by Playwright or similar tools to define available browsers
/// and their revisions.
class BrowserJson {
  /// A comment field often included in the JSON file, typically indicating
  /// how the file was generated.
  final String comment;
  /// A list of browser definitions available in the configuration.
  final List<BrowserEntry> browsers;

  /// Creates a [BrowserJson] instance.
  BrowserJson({
    required this.comment,
    required this.browsers,
  });

  /// Creates a [BrowserJson] instance from a JSON map.
  factory BrowserJson.fromJson(Map<String, dynamic> json) {
    return BrowserJson(
      comment: json['comment'] as String,
      browsers: (json['browsers'] as List)
          .map((e) => BrowserEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Represents a single browser entry within the `browsers.json` file.
class BrowserEntry {
  /// The unique name identifying this executable (e.g., 'chromium', 'ffmpeg').

  /// The registry name of the browser (e.g., 'chromium', 'firefox').

  /// The name of the browser entry (e.g., 'chromium', 'firefox', 'webkit').
  final String name;
  /// The resolved revision number for the current platform.

  /// The default revision number for this browser.
  final String revision;
  /// The user-visible version string associated with this executable (optional).

  /// The user-visible browser version string (optional).

  /// The corresponding user-visible browser version string (optional).
  final String? browserVersion;
  /// Whether this browser is typically installed by default.

  /// Whether this browser should be installed by default during setup.
  final bool installByDefault;
  /// A map of platform identifiers (e.g., 'mac13-arm64') to specific revision
  /// numbers, overriding the default [revision] for those platforms.
  final Map<String, String>? revisionOverrides;

  /// Creates a [BrowserEntry] instance.
  BrowserEntry({
    required this.name,
    required this.revision,
    this.browserVersion,
    required this.installByDefault,
    this.revisionOverrides,
  });

  /// Creates a [BrowserEntry] instance from a JSON map.
  factory BrowserEntry.fromJson(Map<String, dynamic> json) {
    return BrowserEntry(
      name: json['name'] as String,
      revision: json['revision'] as String,
      browserVersion: json['browserVersion'] as String?,
      installByDefault: json['installByDefault'] as bool,
      revisionOverrides: json['revisionOverrides'] != null
          ? Map<String, String>.from(json['revisionOverrides'] as Map)
          : null,
    );
  }
}

/// Describes a specific browser variant, revision, and installation directory
/// resolved for the current platform based on [BrowserEntry] data.
class BrowserDescriptor {
  final String name;
  /// The general name of the browser (e.g., 'chromium', 'firefox'). Derived from [name].
  final String browserName;
  final String revision;
  /// Whether the [revision] was overridden for the current platform.
  final bool hasRevisionOverride;
  final String? browserVersion;
  final bool installByDefault;
  /// The calculated installation directory path for this browser revision.
  final String dir;

  /// Creates a [BrowserDescriptor] instance.
  BrowserDescriptor({
    required this.name,
    required this.browserName,
    required this.revision,
    required this.hasRevisionOverride,
    this.browserVersion,
    required this.installByDefault,
    required this.dir,
  });
}

/// The type of executable managed by the registry.
enum ExecutableType { browser, tool, channel }

/// Describes how an executable should be installed or acquired.
enum InstallType { downloadByDefault, downloadOnDemand, installScript, none }

/// Represents a browser or tool executable that can be managed (downloaded,
/// validated, executed) by the [Registry].
class Executable {
  /// The type of this executable.
  final ExecutableType type;
  final String name;
  /// The general browser type associated with this executable (if applicable).
  final String? browserName;
  /// How this executable is typically installed.
  final InstallType installType;
  /// The installation directory path, if applicable.
  final String? directory;
  /// A list of potential URLs to download the executable archive from.
  final List<String>? downloadURLs;
  final String? browserVersion;
  /// A function that returns the expected path to the executable file within
  /// its installation [directory].
  final String Function() executablePath;
  /// A function that returns the executable path, throwing a [BrowserException]
  /// if the executable is not found or not installed. [sdkLanguage] might be
  /// used for more informative error messages.
  final String Function(String sdkLanguage) executablePathOrDie;
  /// An asynchronous function to validate platform-specific host requirements
  /// needed to run this executable. [sdkLanguage] can provide context.
  final Future<void> Function(String sdkLanguage) validateHostRequirements;
  /// An optional asynchronous function to perform the installation of this
  /// executable, typically involving downloading and extraction.
  final Future<void> Function()? install;

  /// Creates an [Executable] instance.
  Executable({
    required this.type,
    required this.name,
    required this.browserName,
    required this.installType,
    this.directory,
    this.downloadURLs,
    this.browserVersion,
    required this.executablePath,
    required this.executablePathOrDie,
    required this.validateHostRequirements,
    this.install,
  });
}
