class BrowserJson {
  final String comment;
  final List<BrowserEntry> browsers;

  BrowserJson({
    required this.comment,
    required this.browsers,
  });

  factory BrowserJson.fromJson(Map<String, dynamic> json) {
    return BrowserJson(
      comment: json['comment'] as String,
      browsers: (json['browsers'] as List)
          .map((e) => BrowserEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BrowserEntry {
  final String name;
  final String revision;
  final String? browserVersion;
  final bool installByDefault;
  final Map<String, String>? revisionOverrides;

  BrowserEntry({
    required this.name,
    required this.revision,
    this.browserVersion,
    required this.installByDefault,
    this.revisionOverrides,
  });

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

class BrowserDescriptor {
  final String name;
  final String browserName;
  final String revision;
  final bool hasRevisionOverride;
  final String? browserVersion;
  final bool installByDefault;
  final String dir;

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

enum ExecutableType { browser, tool, channel }
enum InstallType { downloadByDefault, downloadOnDemand, installScript, none }

class Executable {
  final ExecutableType type;
  final String name;
  final String? browserName;
  final InstallType installType;
  final String? directory;
  final List<String>? downloadURLs;
  final String? browserVersion;
  final String Function() executablePath;
  final String Function(String sdkLanguage) executablePathOrDie;
  final Future<void> Function(String sdkLanguage) validateHostRequirements;
  final Future<void> Function()? install;

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

