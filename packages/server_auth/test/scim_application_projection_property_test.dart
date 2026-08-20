import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

String _report(PropertyResult result) =>
    'Property failed after ${result.numTests} cases: '
    '${result.error ?? 'unknown failure'}; input=${result.failingInput}; '
    'seed=${result.seed}';

void main() {
  test(
    'hostile projection identifiers fail closed without reflection',
    () async {
      final generator = Gen.frequency<String>([
        (7, Chaos.string(minLength: 0, maxLength: 400)),
        (
          3,
          Gen.oneOf<String>([
            '',
            'valid-id',
            'value\r\nset-cookie: leaked=1',
            'value\u0000suffix',
            'a' * 257,
            '  padded  ',
          ]),
        ),
      ]);
      final runner = PropertyTestRunner<String>(generator, (candidate) {
        try {
          final scope = AuthScimApplicationProjectionScope(
            connectionId: candidate,
            tenantId: 'tenant-a',
            organizationId: 'organization-a',
            provisioningDomainId: 'domain-a',
          );
          expect(scope.connectionId, scope.connectionId.trim());
          expect(scope.connectionId, isNotEmpty);
          expect(scope.connectionId.length, lessThanOrEqualTo(256));
          expect(
            scope.connectionId.codeUnits,
            everyElement(allOf(greaterThanOrEqualTo(0x20), isNot(0x7f))),
          );
        } on ArgumentError catch (error) {
          expect(error.toString(), isNot(contains('set-cookie')));
          expect(error.toString(), isNot(contains('leaked')));
        }
      }, PropertyConfig(numTests: 700, seed: 20260828));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );

  test('generated equal resource IDs never cross connection scopes', () async {
    final runner = PropertyTestRunner<int>(Gen.integer(min: 0, max: 1000000), (
      value,
    ) async {
      final store = InMemoryAuthScimApplicationProjectionStore();
      final resourceId = 'resource-${value.abs()}';
      final first = _subject(resourceId, connectionId: 'connection-a');
      final second = _subject(resourceId, connectionId: 'connection-b');
      await store.apply(_create('create-a-$value', first));
      await store.apply(_create('create-b-$value', second));

      expect((await store.find(first))?.subject, first);
      expect((await store.find(second))?.subject, second);
      expect(
        (await store.list(
          AuthScimApplicationProjectionQuery(scope: first.scope),
        )).records.map((record) => record.subject),
        <AuthScimApplicationProjectionSubject>[first],
      );
    }, PropertyConfig(numTests: 300, seed: 20260829));

    final result = await runner.run();
    expect(result.success, isTrue, reason: _report(result));
  });

  test(
    'stateful mutation sequences preserve fencing and auth isolation',
    () async {
      final generator = Gen.integer(
        min: -10000,
        max: 10000,
      ).list(minLength: 1, maxLength: 60);
      final runner = PropertyTestRunner<List<int>>(generator, (
        operations,
      ) async {
        final store = InMemoryAuthScimApplicationProjectionStore();
        final authStore = InMemoryAuthStore();
        final subject = _subject('directory-user');
        var nextOperation = 0;
        var record = (await store.apply(
          _create('stateful-${nextOperation++}', subject),
        )).record!;
        var deleted = false;

        for (final input in operations) {
          if (deleted) {
            final rejected = await store.apply(
              _create('stateful-${nextOperation++}', subject),
            );
            expect(
              rejected.status,
              AuthScimApplicationProjectionStatus.scopeDeleted,
            );
            continue;
          }
          switch (input.abs() % 4) {
            case 0:
              final updated = await store.apply(
                AuthScimApplicationProjectionCommand(
                  operationId: 'stateful-${nextOperation++}',
                  mutation: AuthScimApplicationProjectionMutation.update,
                  desired: _snapshot(
                    subject,
                    version: 'version-${record.version + 1}',
                    digestSeed: (record.version % 15 + 1).toRadixString(16),
                  ),
                  expectedVersion: record.version,
                ),
              );
              expect(
                updated.status,
                AuthScimApplicationProjectionStatus.applied,
              );
              record = updated.record!;
            case 1:
              final stale = await store.apply(
                AuthScimApplicationProjectionCommand(
                  operationId: 'stateful-${nextOperation++}',
                  mutation: AuthScimApplicationProjectionMutation.update,
                  desired: _snapshot(subject, digestSeed: 'f'),
                  expectedVersion: record.version + 1,
                ),
              );
              expect(
                stale.status,
                AuthScimApplicationProjectionStatus.versionConflict,
              );
            case 2:
              final page = await store.list(
                AuthScimApplicationProjectionQuery(scope: subject.scope),
              );
              final reconciled = await store.reconcile(
                AuthScimApplicationReconciliationCommand(
                  operationId: 'stateful-${nextOperation++}',
                  scope: subject.scope,
                  expectedProjectionSnapshotId: page.projectionSnapshotId,
                  authoritative: <AuthScimApplicationProjectionSnapshot>[
                    record.snapshot,
                  ],
                ),
              );
              expect(reconciled.committed, isTrue);
            case 3:
              if (input % 11 == 0) {
                final page = await store.list(
                  AuthScimApplicationProjectionQuery(scope: subject.scope),
                );
                final result = await store.deleteScope(
                  AuthScimApplicationProjectionScopeDeletionCommand(
                    operationId: 'stateful-${nextOperation++}',
                    scope: subject.scope,
                    expectedProjectionSnapshotId: page.projectionSnapshotId,
                  ),
                );
                expect(result.committed, isTrue);
                deleted = true;
              }
          }
          final page = await store.list(
            AuthScimApplicationProjectionQuery(scope: subject.scope),
          );
          expect(page.total, lessThanOrEqualTo(1));
          expect(await authStore.users.findById(subject.resourceId), isNull);
          expect(
            await authStore.users.findByEmail('directory-user@example.test'),
            isNull,
          );
        }
      }, PropertyConfig(numTests: 180, seed: 20260830));

      final result = await runner.run();
      expect(result.success, isTrue, reason: _report(result));
    },
  );

  test('generated cross-scope group members are always rejected', () async {
    final runner = PropertyTestRunner<int>(Gen.integer(min: 0, max: 1000000), (
      value,
    ) {
      final group = _subject(
        'group-$value',
        kind: AuthScimApplicationSubjectKind.group,
      );
      final foreign = _subject('user-$value', connectionId: 'connection-b');
      expect(
        () => _snapshot(
          group,
          members: <AuthScimApplicationProjectionSubject>[foreign],
        ),
        throwsArgumentError,
      );
    }, PropertyConfig(numTests: 500, seed: 20260831));

    final result = await runner.run();
    expect(result.success, isTrue, reason: _report(result));
  });
}

AuthScimApplicationProjectionSubject _subject(
  String resourceId, {
  String connectionId = 'connection-a',
  AuthScimApplicationSubjectKind kind = AuthScimApplicationSubjectKind.user,
}) => AuthScimApplicationProjectionSubject(
  scope: AuthScimApplicationProjectionScope(
    connectionId: connectionId,
    tenantId: 'tenant-a',
    organizationId: 'organization-a',
    provisioningDomainId: 'domain-a',
  ),
  resourceId: resourceId,
  kind: kind,
);

AuthScimApplicationProjectionSnapshot _snapshot(
  AuthScimApplicationProjectionSubject subject, {
  String version = 'version-1',
  String digestSeed = 'a',
  Iterable<AuthScimApplicationProjectionSubject> members =
      const <AuthScimApplicationProjectionSubject>[],
}) => AuthScimApplicationProjectionSnapshot(
  subject: subject,
  sourceVersion: version,
  sourceDigest: digestSeed * 64,
  state: AuthScimApplicationProjectionState.active,
  members: members,
);

AuthScimApplicationProjectionCommand _create(
  String operationId,
  AuthScimApplicationProjectionSubject subject,
) => AuthScimApplicationProjectionCommand(
  operationId: operationId,
  mutation: AuthScimApplicationProjectionMutation.create,
  desired: _snapshot(subject),
);
