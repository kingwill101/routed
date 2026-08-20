import 'package:test/test.dart';

import '../tool/pub_release_audit.dart';

void main() {
  group('compareVersions', () {
    test('compares release versions numerically', () {
      expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
      expect(compareVersions('0.3.3', '0.3.3'), 0);
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
    });

    test('follows prerelease precedence', () {
      expect(compareVersions('1.0.0-alpha', '1.0.0'), lessThan(0));
      expect(compareVersions('1.0.0-alpha.2', '1.0.0-alpha.10'), lessThan(0));
      expect(compareVersions('1.0.0-beta', '1.0.0-alpha'), greaterThan(0));
    });

    test('ignores build metadata for precedence', () {
      expect(compareVersions('0.1.0+2', '0.1.0+1'), 0);
    });
  });

  group('versionSatisfiesConstraint', () {
    test(
      'supports hosted dependency constraint forms used by the workspace',
      () {
        expect(versionSatisfiesConstraint('0.4.0', 'any'), isTrue);
        expect(versionSatisfiesConstraint('0.4.2', '>=0.4.0 <1.0.0'), isTrue);
        expect(versionSatisfiesConstraint('1.0.0', '>=0.4.0 <1.0.0'), isFalse);
        expect(versionSatisfiesConstraint('1.9.0', '^1.2.3'), isTrue);
        expect(versionSatisfiesConstraint('2.0.0', '^1.2.3'), isFalse);
        expect(versionSatisfiesConstraint('0.2.9', '^0.2.3'), isTrue);
        expect(versionSatisfiesConstraint('0.3.0', '^0.2.3'), isFalse);
        expect(versionSatisfiesConstraint('0.0.4', '^0.0.3'), isFalse);
      },
    );
  });

  group('buildReleasePlan', () {
    test('orders workspace dependencies before their consumers', () {
      final plan = buildReleasePlan([
        audit('facade', dependencies: {'adapter': '>=1.0.0 <2.0.0'}),
        audit('core'),
        audit('adapter', dependencies: {'core': '^1.0.0'}),
      ]);

      expect(plan.publishOrder, ['core', 'adapter', 'facade']);
      expect(plan.cycles, isEmpty);
      expect(plan.issues, isEmpty);
    });

    test('reports cycles and omits transitively blocked consumers', () {
      final plan = buildReleasePlan([
        audit('a', dependencies: {'b': '^1.0.0'}),
        audit('b', dependencies: {'a': '^1.0.0'}),
        audit('consumer', dependencies: {'a': '^1.0.0'}),
        audit('independent'),
      ]);

      expect(plan.cycles, [
        ['a', 'b'],
      ]);
      expect(plan.cycleBlockedPackages, ['a', 'b', 'consumer']);
      expect(plan.publishOrder, ['independent']);
      expect(plan.hasBlockers, isTrue);
    });

    test('warns when only a published version satisfies the constraint', () {
      final plan = buildReleasePlan([
        audit('consumer', dependencies: {'core': '^1.0.0'}),
        audit(
          'core',
          version: '2.0.0',
          publishedVersions: const ['1.5.0', '2.0.0'],
        ),
      ]);

      expect(plan.publishOrder, ['consumer', 'core']);
      expect(plan.issues, hasLength(1));
      expect(plan.issues.single.kind, DependencyIssueKind.localVersionMismatch);
      expect(plan.issues.single.blocking, isFalse);
      expect(plan.hasBlockers, isFalse);
    });

    test('blocks when neither local nor published versions satisfy', () {
      final plan = buildReleasePlan([
        audit('consumer', dependencies: {'core': '>=2.0.0 <3.0.0'}),
        audit(
          'core',
          version: '1.2.0',
          publishedVersions: const ['1.0.0', '1.1.0'],
        ),
      ]);

      expect(
        plan.issues.single.kind,
        DependencyIssueKind.unavailableWorkspaceDependency,
      );
      expect(plan.issues.single.blocking, isTrue);
      expect(plan.hasBlockers, isTrue);
    });

    test('blocks clean consumers from private workspace-only dependencies', () {
      final plan = buildReleasePlan([
        audit('consumer', dependencies: {'internal': '^1.0.0'}),
        audit('internal', publishable: false),
      ]);

      expect(
        plan.issues.single.kind,
        DependencyIssueKind.privateWorkspaceDependency,
      );
      expect(plan.issues.single.blocking, isTrue);
    });

    test('blocks path dependencies even when their versions match', () {
      final plan = buildReleasePlan([
        audit(
          'consumer',
          dependencyRecords: {
            'core': const PackageDependency(
              name: 'core',
              constraint: '^1.0.0',
              source: DependencySource.path,
            ),
          },
        ),
        audit('core'),
      ]);

      expect(plan.issues.single.kind, DependencyIssueKind.unsupportedSource);
      expect(plan.issues.single.blocking, isTrue);
    });
  });
}

PackageAudit audit(
  String name, {
  String version = '1.0.0',
  bool publishable = true,
  Map<String, String> dependencies = const {},
  Map<String, PackageDependency>? dependencyRecords,
  List<String> publishedVersions = const [],
}) {
  final records =
      dependencyRecords ??
      {
        for (final entry in dependencies.entries)
          entry.key: PackageDependency(
            name: entry.key,
            constraint: entry.value,
            source: DependencySource.hosted,
          ),
      };
  return PackageAudit(
    manifest: PackageManifest(
      name: name,
      version: version,
      relativePath: 'packages/$name',
      changelog: ChangelogState.versioned,
      publishable: publishable,
      dependencies: records,
    ),
    release: PubRelease(
      version: publishedVersions.isEmpty ? null : publishedVersions.last,
      versions: publishedVersions,
    ),
  );
}
