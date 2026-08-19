import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const _usage = '''
Compare workspace package versions with their latest pub.dev releases.

Usage: dart run tool/pub_release_audit.dart [options]

Options:
  --root <path>  Workspace root to inspect (default: current directory)
  --json         Emit machine-readable JSON instead of a table
  --check        Exit 1 when a published package is not ahead of pub.dev
  -h, --help     Show this help
''';

class PackageManifest {
  PackageManifest({
    required this.name,
    required this.version,
    required this.relativePath,
    required this.changelog,
    required this.publishable,
  });

  final String name;
  final String version;
  final String relativePath;
  final ChangelogState changelog;
  final bool publishable;
}

enum ChangelogState { unreleased, versioned, missing }

class PubRelease {
  const PubRelease({this.version, this.error});

  final String? version;
  final String? error;
}

class PackageAudit {
  PackageAudit({required this.manifest, required this.release});

  final PackageManifest manifest;
  final PubRelease release;

  String get status {
    if (!manifest.publishable) return 'private';
    if (release.error != null) return 'error';
    final latest = release.version;
    if (latest == null) return 'unpublished';
    if (manifest.version == latest) return 'same';

    final comparison = compareVersions(manifest.version, latest);
    if (comparison > 0) return 'ahead';
    if (comparison < 0) return 'behind';
    return 'different-build';
  }

  Map<String, Object?> toJson() => {
    'name': manifest.name,
    'path': manifest.relativePath,
    'local': manifest.version,
    'latest': release.version,
    'status': status,
    'changelog': manifest.changelog.name,
    if (release.error != null) 'error': release.error,
  };
}

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options.help) {
    stdout.write(_usage);
    return;
  }

  final root = Directory(options.root).absolute;
  final manifests = loadWorkspaceManifests(root);
  if (manifests.isEmpty) {
    throw StateError('No workspace packages were found under ${root.path}.');
  }

  final client = PubDevClient();
  try {
    final audits = await Future.wait(
      manifests.map((manifest) async {
        if (!manifest.publishable) {
          return PackageAudit(manifest: manifest, release: const PubRelease());
        }
        return PackageAudit(
          manifest: manifest,
          release: await client.latest(manifest.name),
        );
      }),
    );
    audits.sort((a, b) => a.manifest.name.compareTo(b.manifest.name));

    if (options.json) {
      stdout.writeln(
        jsonEncode(audits.map((audit) => audit.toJson()).toList()),
      );
    } else {
      writeTable(audits);
    }

    if (options.check && audits.any(_needsVersionAction)) {
      exitCode = 1;
    }
  } finally {
    client.close();
  }
}

bool _needsVersionAction(PackageAudit audit) {
  return audit.status == 'same' ||
      audit.status == 'behind' ||
      audit.status == 'different-build' ||
      audit.status == 'error';
}

List<PackageManifest> loadWorkspaceManifests(Directory root) {
  final rootPubspec = File(p.join(root.path, 'pubspec.yaml'));
  if (!rootPubspec.existsSync()) {
    throw StateError('Missing workspace pubspec.yaml at ${rootPubspec.path}.');
  }

  final document = loadYaml(rootPubspec.readAsStringSync());
  final workspace = document['workspace'];
  if (workspace is! YamlList) {
    throw StateError('The root pubspec.yaml does not define a workspace.');
  }

  final manifests = <PackageManifest>[];
  for (final entry in workspace.whereType<String>()) {
    if (!entry.startsWith('packages/') || entry.contains('/example/')) {
      continue;
    }
    final packageDirectory = Directory(p.join(root.path, entry));
    final pubspec = File(p.join(packageDirectory.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) continue;

    final package = loadYaml(pubspec.readAsStringSync());
    final name = package['name'];
    final version = package['version'];
    if (name is! String || version is! String) continue;

    final publishTo = package['publish_to'];
    manifests.add(
      PackageManifest(
        name: name,
        version: version,
        relativePath: entry,
        changelog: readChangelog(packageDirectory),
        publishable: publishTo != 'none',
      ),
    );
  }
  return manifests;
}

ChangelogState readChangelog(Directory packageDirectory) {
  final changelog = File(p.join(packageDirectory.path, 'CHANGELOG.md'));
  if (!changelog.existsSync()) return ChangelogState.missing;
  final firstHeading = changelog.readAsLinesSync().firstWhere(
    (line) => line.startsWith('## '),
    orElse: () => '',
  );
  return firstHeading.trim() == '## Unreleased'
      ? ChangelogState.unreleased
      : ChangelogState.versioned;
}

class PubDevClient {
  PubDevClient() : _client = HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 15);
  }

  final HttpClient _client;

  Future<PubRelease> latest(String packageName) async {
    try {
      final request = await _client
          .getUrl(Uri.https('pub.dev', '/api/packages/$packageName'))
          .timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.notFound) {
        return const PubRelease();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return PubRelease(
          error: 'HTTP ${response.statusCode}: ${_compact(body)}',
        );
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      final latest = data['latest'] as Map<String, dynamic>?;
      final version = latest?['version'];
      if (version is! String || version.isEmpty) {
        return const PubRelease(
          error: 'pub.dev response has no latest version',
        );
      }
      return PubRelease(version: version);
    } on Object catch (error) {
      return PubRelease(error: error.toString());
    }
  }

  void close() => _client.close(force: true);
}

String _compact(String value) {
  final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return compact.length <= 120 ? compact : '${compact.substring(0, 117)}...';
}

int compareVersions(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  for (var index = 0; index < 3; index++) {
    final comparison = leftParts.core[index].compareTo(rightParts.core[index]);
    if (comparison != 0) return comparison;
  }

  final leftPre = leftParts.prerelease;
  final rightPre = rightParts.prerelease;
  if (leftPre == null && rightPre == null) return 0;
  if (leftPre == null) return 1;
  if (rightPre == null) return -1;
  final length = leftPre.length < rightPre.length
      ? leftPre.length
      : rightPre.length;
  for (var index = 0; index < length; index++) {
    final leftPart = leftPre[index];
    final rightPart = rightPre[index];
    if (leftPart == rightPart) continue;
    final leftNumber = int.tryParse(leftPart);
    final rightNumber = int.tryParse(rightPart);
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    if (leftNumber != null) return -1;
    if (rightNumber != null) return 1;
    return leftPart.compareTo(rightPart);
  }
  return leftPre.length.compareTo(rightPre.length);
}

({List<int> core, List<String>? prerelease}) _versionParts(String value) {
  final withoutBuild = value.split('+').first;
  final separator = withoutBuild.indexOf('-');
  final corePart = separator == -1
      ? withoutBuild
      : withoutBuild.substring(0, separator);
  final prereleasePart = separator == -1
      ? null
      : withoutBuild.substring(separator + 1);
  final core = corePart.split('.').map(int.parse).toList();
  while (core.length < 3) {
    core.add(0);
  }
  return (
    core: core.take(3).toList(growable: false),
    prerelease: prereleasePart?.split('.'),
  );
}

void writeTable(List<PackageAudit> audits) {
  const headers = [
    'PACKAGE',
    'LOCAL',
    'PUB.DEV',
    'STATUS',
    'CHANGELOG',
    'PATH',
  ];
  final rows = audits
      .map(
        (audit) => [
          audit.manifest.name,
          audit.manifest.version,
          audit.release.version ??
              (audit.release.error == null ? '—' : 'error'),
          audit.status,
          audit.manifest.changelog.name,
          audit.manifest.relativePath,
        ],
      )
      .toList();
  final widths = List<int>.generate(
    headers.length,
    (index) => [
      headers[index].length,
      ...rows.map((row) => row[index].length),
    ].reduce((a, b) => a > b ? a : b),
  );
  String formatRow(List<String> row) => row
      .asMap()
      .entries
      .map((entry) => entry.value.padRight(widths[entry.key]))
      .join('  ');

  stdout.writeln(formatRow(headers));
  stdout.writeln(widths.map((width) => '-' * width).join('  '));
  for (final row in rows) {
    stdout.writeln(formatRow(row));
    if (row[3] == 'error') {
      final audit = audits.firstWhere((audit) => audit.manifest.name == row[0]);
      stderr.writeln('${row[0]}: ${audit.release.error}');
    }
  }
}

class _Options {
  _Options() : root = '.', json = false, check = false, help = false;

  String root;
  bool json;
  bool check;
  bool help;
}

_Options _parseArgs(List<String> args) {
  final options = _Options();
  for (var index = 0; index < args.length; index++) {
    switch (args[index]) {
      case '-h':
      case '--help':
        options.help = true;
      case '--json':
        options.json = true;
      case '--check':
        options.check = true;
      case '--root':
        if (index + 1 >= args.length) {
          throw ArgumentError('--root requires a path.');
        }
        options.root = args[++index];
      default:
        throw ArgumentError('Unknown option: ${args[index]}');
    }
  }
  return options;
}
