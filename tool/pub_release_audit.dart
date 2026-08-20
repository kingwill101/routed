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
  --check        Exit 1 on version or dependency release blockers
  -h, --help     Show this help
''';

enum DependencySource { hosted, path, git, sdk, unknown }

class PackageDependency {
  const PackageDependency({
    required this.name,
    required this.constraint,
    required this.source,
  });

  final String name;
  final String constraint;
  final DependencySource source;
}

class PackageManifest {
  PackageManifest({
    required this.name,
    required this.version,
    required this.relativePath,
    required this.changelog,
    required this.publishable,
    this.dependencies = const {},
  });

  final String name;
  final String version;
  final String relativePath;
  final ChangelogState changelog;
  final bool publishable;
  final Map<String, PackageDependency> dependencies;
}

enum ChangelogState { unreleased, versioned, missing }

class PubRelease {
  const PubRelease({this.version, this.versions = const [], this.error});

  final String? version;
  final List<String> versions;
  final String? error;
}

enum DependencyIssueKind {
  localVersionMismatch,
  unavailableWorkspaceDependency,
  privateWorkspaceDependency,
  unsupportedSource,
  registryLookupFailed,
}

class DependencyIssue {
  const DependencyIssue({
    required this.package,
    required this.dependency,
    required this.constraint,
    required this.kind,
    required this.message,
    required this.blocking,
  });

  final String package;
  final String dependency;
  final String constraint;
  final DependencyIssueKind kind;
  final String message;
  final bool blocking;

  Map<String, Object?> toJson() => {
    'package': package,
    'dependency': dependency,
    'constraint': constraint,
    'kind': kind.name,
    'blocking': blocking,
    'message': message,
  };
}

class ReleasePlan {
  const ReleasePlan({
    required this.publishOrder,
    required this.cycles,
    required this.cycleBlockedPackages,
    required this.issues,
  });

  final List<String> publishOrder;
  final List<List<String>> cycles;
  final List<String> cycleBlockedPackages;
  final List<DependencyIssue> issues;

  bool get hasBlockers =>
      cycles.isNotEmpty || issues.any((issue) => issue.blocking);

  Map<String, Object?> toJson() => {
    'publishOrder': publishOrder,
    'cycles': cycles,
    'cycleBlockedPackages': cycleBlockedPackages,
    'dependencyIssues': issues.map((issue) => issue.toJson()).toList(),
  };
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
    final releasePlan = buildReleasePlan(audits);

    if (options.json) {
      stdout.writeln(
        jsonEncode({
          'packages': audits.map((audit) => audit.toJson()).toList(),
          ...releasePlan.toJson(),
        }),
      );
    } else {
      writeTable(audits);
      writeReleasePlan(releasePlan, audits);
    }

    if (options.check &&
        (audits.any(_needsVersionAction) || releasePlan.hasBlockers)) {
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
    final dependencies = _readDependencies(package['dependencies']);
    manifests.add(
      PackageManifest(
        name: name,
        version: version,
        relativePath: entry,
        changelog: readChangelog(packageDirectory),
        publishable: publishTo != 'none',
        dependencies: dependencies,
      ),
    );
  }
  return manifests;
}

Map<String, PackageDependency> _readDependencies(Object? value) {
  if (value is! YamlMap) return const {};
  return {
    for (final entry in value.entries)
      if (entry.key is String)
        entry.key as String: _readDependency(entry.key as String, entry.value),
  };
}

PackageDependency _readDependency(String name, Object? value) {
  if (value == null || value is String) {
    return PackageDependency(
      name: name,
      constraint: value as String? ?? 'any',
      source: DependencySource.hosted,
    );
  }
  if (value is YamlMap) {
    final source = switch (value) {
      {'path': _} => DependencySource.path,
      {'git': _} => DependencySource.git,
      {'sdk': _} => DependencySource.sdk,
      {'hosted': _} => DependencySource.hosted,
      _ => DependencySource.unknown,
    };
    final constraint = value['version'];
    return PackageDependency(
      name: name,
      constraint: constraint is String ? constraint : 'any',
      source: source,
    );
  }
  return PackageDependency(
    name: name,
    constraint: 'any',
    source: DependencySource.unknown,
  );
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
      final releases = data['versions'];
      final versions = releases is List
          ? releases
                .whereType<Map<String, dynamic>>()
                .map((release) => release['version'])
                .whereType<String>()
                .toList(growable: false)
          : <String>[version];
      return PubRelease(version: version, versions: versions);
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

bool versionSatisfiesConstraint(String version, String constraint) {
  final normalized = constraint.trim();
  if (normalized.isEmpty || normalized == 'any') return true;
  return normalized
      .split('||')
      .any(
        (alternative) => _satisfiesConstraintSet(version, alternative.trim()),
      );
}

bool _satisfiesConstraintSet(String version, String constraint) {
  if (constraint.startsWith('^')) {
    final minimum = constraint.substring(1).trim();
    if (compareVersions(version, minimum) < 0) return false;
    return compareVersions(version, _caretUpperBound(minimum)) < 0;
  }

  final normalized = constraint.replaceAllMapped(
    RegExp(r'(>=|<=|>|<|=)\s+'),
    (match) => match.group(1)!,
  );
  final comparisons = normalized
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map(RegExp(r'^(>=|<=|>|<|=)?(.+)$').firstMatch)
      .whereType<RegExpMatch>()
      .toList(growable: false);
  if (comparisons.isEmpty) return false;
  return comparisons.every((match) {
    final operator = match.group(1) ?? '=';
    final target = match.group(2)!;
    final comparison = compareVersions(version, target);
    return switch (operator) {
      '>=' => comparison >= 0,
      '<=' => comparison <= 0,
      '>' => comparison > 0,
      '<' => comparison < 0,
      _ => comparison == 0,
    };
  });
}

String _caretUpperBound(String minimum) {
  final parts = _versionParts(minimum).core;
  final firstNonZero = parts.indexWhere((part) => part != 0);
  final bumpIndex = firstNonZero == -1 ? 2 : firstNonZero;
  final upper = List<int>.from(parts);
  upper[bumpIndex]++;
  for (var index = bumpIndex + 1; index < upper.length; index++) {
    upper[index] = 0;
  }
  return upper.join('.');
}

ReleasePlan buildReleasePlan(List<PackageAudit> audits) {
  final auditsByName = {for (final audit in audits) audit.manifest.name: audit};
  final publishable = {
    for (final audit in audits)
      if (audit.manifest.publishable) audit.manifest.name: audit,
  };
  final dependencies = {for (final name in publishable.keys) name: <String>{}};
  final issues = <DependencyIssue>[];

  for (final audit in publishable.values) {
    for (final dependency in audit.manifest.dependencies.values) {
      final workspaceAudit = auditsByName[dependency.name];
      if (workspaceAudit == null) continue;

      if (dependency.source != DependencySource.hosted) {
        issues.add(
          DependencyIssue(
            package: audit.manifest.name,
            dependency: dependency.name,
            constraint: dependency.constraint,
            kind: DependencyIssueKind.unsupportedSource,
            blocking: true,
            message:
                'uses a ${dependency.source.name} source; a clean pub.dev '
                'consumer cannot resolve the workspace checkout',
          ),
        );
        continue;
      }

      final localSatisfies = versionSatisfiesConstraint(
        workspaceAudit.manifest.version,
        dependency.constraint,
      );
      final publishedSatisfies = workspaceAudit.release.versions.any(
        (version) => versionSatisfiesConstraint(version, dependency.constraint),
      );

      if (workspaceAudit.manifest.publishable && localSatisfies) {
        dependencies[audit.manifest.name]!.add(dependency.name);
      } else if (!workspaceAudit.manifest.publishable) {
        issues.add(
          DependencyIssue(
            package: audit.manifest.name,
            dependency: dependency.name,
            constraint: dependency.constraint,
            kind: DependencyIssueKind.privateWorkspaceDependency,
            blocking: !publishedSatisfies,
            message: publishedSatisfies
                ? 'depends on a private workspace package; pub.dev has a '
                      'compatible fallback, but local changes cannot be released'
                : 'depends on a private workspace package with no compatible '
                      'pub.dev release',
          ),
        );
      } else if (publishedSatisfies) {
        issues.add(
          DependencyIssue(
            package: audit.manifest.name,
            dependency: dependency.name,
            constraint: dependency.constraint,
            kind: DependencyIssueKind.localVersionMismatch,
            blocking: false,
            message:
                'local ${workspaceAudit.manifest.version} is outside the '
                'constraint; a published version is compatible',
          ),
        );
      } else if (workspaceAudit.release.error != null) {
        issues.add(
          DependencyIssue(
            package: audit.manifest.name,
            dependency: dependency.name,
            constraint: dependency.constraint,
            kind: DependencyIssueKind.registryLookupFailed,
            blocking: true,
            message:
                'local ${workspaceAudit.manifest.version} is outside the '
                'constraint and pub.dev lookup failed: '
                '${workspaceAudit.release.error}',
          ),
        );
      } else {
        issues.add(
          DependencyIssue(
            package: audit.manifest.name,
            dependency: dependency.name,
            constraint: dependency.constraint,
            kind: DependencyIssueKind.unavailableWorkspaceDependency,
            blocking: true,
            message:
                'neither local ${workspaceAudit.manifest.version} nor any '
                'published version satisfies the constraint',
          ),
        );
      }
    }
  }

  final cycles = _dependencyCycles(dependencies);
  final cycleBlockedPackages = cycles.expand((cycle) => cycle).toSet();
  var changed = true;
  while (changed) {
    changed = false;
    for (final entry in dependencies.entries) {
      if (!cycleBlockedPackages.contains(entry.key) &&
          entry.value.any(cycleBlockedPackages.contains)) {
        cycleBlockedPackages.add(entry.key);
        changed = true;
      }
    }
  }
  final publishOrder = _topologicalOrder(dependencies, cycleBlockedPackages);
  issues.sort((left, right) {
    final packageComparison = left.package.compareTo(right.package);
    return packageComparison != 0
        ? packageComparison
        : left.dependency.compareTo(right.dependency);
  });
  return ReleasePlan(
    publishOrder: publishOrder,
    cycles: cycles,
    cycleBlockedPackages: cycleBlockedPackages.toList()..sort(),
    issues: issues,
  );
}

List<String> _topologicalOrder(
  Map<String, Set<String>> dependencies,
  Set<String> excluded,
) {
  final remaining = {
    for (final entry in dependencies.entries)
      if (!excluded.contains(entry.key))
        entry.key: entry.value
            .where((name) => !excluded.contains(name))
            .toSet(),
  };
  final order = <String>[];
  while (remaining.isNotEmpty) {
    final ready =
        remaining.entries
            .where((entry) => entry.value.isEmpty)
            .map((entry) => entry.key)
            .toList(growable: false)
          ..sort();
    if (ready.isEmpty) break;
    for (final name in ready) {
      remaining.remove(name);
      order.add(name);
    }
    for (final pending in remaining.values) {
      pending.removeAll(ready);
    }
  }
  return order;
}

List<List<String>> _dependencyCycles(Map<String, Set<String>> dependencies) {
  var nextIndex = 0;
  final indexes = <String, int>{};
  final lowLinks = <String, int>{};
  final stack = <String>[];
  final onStack = <String>{};
  final cycles = <List<String>>[];

  void visit(String name) {
    indexes[name] = nextIndex;
    lowLinks[name] = nextIndex;
    nextIndex++;
    stack.add(name);
    onStack.add(name);

    for (final dependency in dependencies[name]!) {
      if (!indexes.containsKey(dependency)) {
        visit(dependency);
        lowLinks[name] = lowLinks[name]! < lowLinks[dependency]!
            ? lowLinks[name]!
            : lowLinks[dependency]!;
      } else if (onStack.contains(dependency)) {
        lowLinks[name] = lowLinks[name]! < indexes[dependency]!
            ? lowLinks[name]!
            : indexes[dependency]!;
      }
    }

    if (lowLinks[name] != indexes[name]) return;
    final component = <String>[];
    String member;
    do {
      member = stack.removeLast();
      onStack.remove(member);
      component.add(member);
    } while (member != name);
    if (component.length > 1 || dependencies[name]!.contains(name)) {
      component.sort();
      cycles.add(component);
    }
  }

  final names = dependencies.keys.toList(growable: false)..sort();
  for (final name in names) {
    if (!indexes.containsKey(name)) visit(name);
  }
  cycles.sort((left, right) => left.first.compareTo(right.first));
  return cycles;
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

void writeReleasePlan(ReleasePlan plan, List<PackageAudit> audits) {
  final auditsByName = {for (final audit in audits) audit.manifest.name: audit};
  stdout.writeln();
  stdout.writeln('PUBLISH ORDER');
  if (plan.publishOrder.isEmpty) {
    stdout.writeln('  No packages can be ordered.');
  } else {
    for (var index = 0; index < plan.publishOrder.length; index++) {
      final name = plan.publishOrder[index];
      final version = auditsByName[name]!.manifest.version;
      stdout.writeln('  ${index + 1}. $name $version');
    }
  }

  if (plan.cycles.isNotEmpty) {
    stdout.writeln();
    stdout.writeln('DEPENDENCY CYCLES');
    for (final cycle in plan.cycles) {
      stdout.writeln('  ${[...cycle, cycle.first].join(' -> ')}');
    }
    final dependents = plan.cycleBlockedPackages
        .where((name) => !plan.cycles.any((cycle) => cycle.contains(name)))
        .toList(growable: false);
    if (dependents.isNotEmpty) {
      stdout.writeln('  Also blocked by cycles: ${dependents.join(', ')}');
    }
  }

  stdout.writeln();
  stdout.writeln('DEPENDENCY READINESS');
  if (plan.issues.isEmpty) {
    stdout.writeln(
      '  Ready: workspace dependency constraints are satisfiable.',
    );
  } else {
    for (final issue in plan.issues) {
      final severity = issue.blocking ? 'BLOCKER' : 'WARNING';
      stdout.writeln(
        '  $severity ${issue.package} -> ${issue.dependency} '
        '(${issue.constraint}): ${issue.message}',
      );
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
