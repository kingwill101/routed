import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('SCIM application projection contracts', () {
    test('keys subjects only by exact scope, resource ID, and kind', () {
      final scope = _scope();
      final same = AuthScimApplicationProjectionSubject(
        scope: _scope(),
        resourceId: 'resource-a',
        kind: AuthScimApplicationSubjectKind.user,
      );
      final subject = AuthScimApplicationProjectionSubject(
        scope: scope,
        resourceId: 'resource-a',
        kind: AuthScimApplicationSubjectKind.user,
      );
      final otherConnection = AuthScimApplicationProjectionSubject(
        scope: _scope(connectionId: 'connection-b'),
        resourceId: 'resource-a',
        kind: AuthScimApplicationSubjectKind.user,
      );
      final group = AuthScimApplicationProjectionSubject(
        scope: scope,
        resourceId: 'resource-a',
        kind: AuthScimApplicationSubjectKind.group,
      );

      expect(subject, same);
      expect(subject, isNot(otherConnection));
      expect(subject, isNot(group));
    });

    test('rejects cross-binding, duplicate, and invalid memberships', () {
      final group = _subject(
        'group-a',
        kind: AuthScimApplicationSubjectKind.group,
      );
      final member = _subject('user-a');
      expect(
        () => _snapshot(
          group,
          members: <AuthScimApplicationProjectionSubject>[member, member],
        ),
        throwsArgumentError,
      );
      expect(
        () => _snapshot(
          group,
          members: <AuthScimApplicationProjectionSubject>[
            _subject('user-a', scope: _scope(connectionId: 'connection-b')),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _snapshot(
          _subject('user-a'),
          members: <AuthScimApplicationProjectionSubject>[member],
        ),
        throwsArgumentError,
      );
      expect(
        () => _snapshot(
          group,
          state: AuthScimApplicationProjectionState.tombstoned,
          members: <AuthScimApplicationProjectionSubject>[member],
        ),
        throwsArgumentError,
      );
    });

    test('source snapshot digests are canonical and order-independent', () {
      final scope = _scope();
      final first = _snapshot(_subject('first'));
      final second = _snapshot(_subject('second'), digestSeed: 'b');
      expect(
        authScimApplicationSourceSnapshotId(
          scope,
          <AuthScimApplicationProjectionSnapshot>[first, second],
        ),
        authScimApplicationSourceSnapshotId(
          scope,
          <AuthScimApplicationProjectionSnapshot>[second, first],
        ),
      );
      expect(
        authScimApplicationSourceSnapshotId(
          scope,
          const <AuthScimApplicationProjectionSnapshot>[],
        ),
        authScimEmptyApplicationProjectionSnapshotId,
      );
    });

    test('mutation payload binding is derived from typed desired state', () {
      final subject = _subject('resource-a');
      final first = AuthScimApplicationProjectionCommand(
        operationId: 'operation-a',
        mutation: AuthScimApplicationProjectionMutation.create,
        desired: _snapshot(subject),
      );
      final same = AuthScimApplicationProjectionCommand(
        operationId: 'another-operation',
        mutation: AuthScimApplicationProjectionMutation.create,
        desired: _snapshot(subject),
      );
      final changed = AuthScimApplicationProjectionCommand(
        operationId: 'operation-a',
        mutation: AuthScimApplicationProjectionMutation.create,
        desired: _snapshot(subject, digestSeed: 'b'),
      );

      expect(first.payloadDigest, same.payloadDigest);
      expect(first.payloadDigest, isNot(changed.payloadDigest));
    });

    test('projection pages reject records from another scope', () {
      expect(
        () => AuthScimApplicationProjectionPage(
          scope: _scope(),
          records: <AuthScimApplicationProjectionRecord>[
            AuthScimApplicationProjectionRecord(
              snapshot: _snapshot(
                _subject(
                  'resource-a',
                  scope: _scope(connectionId: 'connection-b'),
                ),
              ),
              version: 1,
              updatedAt: DateTime.utc(2030),
            ),
          ],
          total: 1,
          projectionSnapshotId: authScimEmptyApplicationProjectionSnapshotId,
        ),
        throwsArgumentError,
      );
    });

    test(
      'projection state cannot create a user or authentication method',
      () async {
        final authStore = InMemoryAuthStore();
        final projectionStore = InMemoryAuthScimApplicationProjectionStore();
        final subject = _subject('directory-user');
        await projectionStore.apply(
          AuthScimApplicationProjectionCommand(
            operationId: 'projection-only',
            mutation: AuthScimApplicationProjectionMutation.create,
            desired: _snapshot(subject),
          ),
        );

        expect(await authStore.users.findById(subject.resourceId), isNull);
        expect(
          await authStore.users.findByEmail('person@example.test'),
          isNull,
        );
        expect(projectionStore, isNot(isA<AuthStore>()));
      },
    );

    test(
      'SCIM protocol topology advertises no sign-in or user deletion hook',
      () {
        final plugin = ScimPlugin<Object>(
          store: const _NoopScimStore(),
          tokenResolver: const _NoopResolver(),
        );

        expect(
          plugin,
          isNot(isA<AuthAuthenticationMethodInventoryContributor>()),
        );
        expect(
          plugin,
          isNot(isA<AuthAuthenticationLifecycleContributor<Object>>()),
        );
        expect(plugin, isNot(isA<AuthUserDeletionPlanContributor>()));
        expect(plugin, isNot(isA<AuthClientOperationContributor>()));
      },
    );
  });
}

AuthScimApplicationProjectionScope _scope({
  String connectionId = 'connection-a',
}) => AuthScimApplicationProjectionScope(
  connectionId: connectionId,
  tenantId: 'tenant-a',
  organizationId: 'organization-a',
  provisioningDomainId: 'domain-a',
);

AuthScimApplicationProjectionSubject _subject(
  String resourceId, {
  AuthScimApplicationProjectionScope? scope,
  AuthScimApplicationSubjectKind kind = AuthScimApplicationSubjectKind.user,
}) => AuthScimApplicationProjectionSubject(
  scope: scope ?? _scope(),
  resourceId: resourceId,
  kind: kind,
);

AuthScimApplicationProjectionSnapshot _snapshot(
  AuthScimApplicationProjectionSubject subject, {
  String digestSeed = 'a',
  AuthScimApplicationProjectionState state =
      AuthScimApplicationProjectionState.active,
  Iterable<AuthScimApplicationProjectionSubject> members =
      const <AuthScimApplicationProjectionSubject>[],
}) => AuthScimApplicationProjectionSnapshot(
  subject: subject,
  sourceVersion: 'version-a',
  sourceDigest: digestSeed * 64,
  state: state,
  members: members,
);

final class _NoopResolver implements AuthScimBearerTokenResolver<Object> {
  const _NoopResolver();

  @override
  AuthScimConnectionIdentity? resolve(
    AuthScimBearerTokenRequest<Object> request,
  ) => null;
}

final class _NoopScimStore implements AuthScimProvisioningStore {
  const _NoopScimStore();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
