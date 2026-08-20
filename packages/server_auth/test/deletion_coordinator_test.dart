import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('AuthInMemoryUserDeletionCoordinator', () {
    test('fails closed until the contributor topology is bound', () async {
      final store = InMemoryAuthStore();
      await store.users.create(AuthUser(id: 'user-1'));

      await expectLater(
        store.userDeletionCoordinator.deleteUser('user-1'),
        throwsStateError,
      );
      expect(await store.users.findById('user-1'), isNotNull);
    });

    test('rejects foreign plans before any mutation', () async {
      final first = InMemoryAuthStore();
      final second = InMemoryAuthStore();
      first.bindUserDeletionPlanContributors(const []);
      second.bindUserDeletionPlanContributors(const []);
      await first.users.create(AuthUser(id: 'user-1'));
      final foreign = AuthNoopUserDeletionPlan(
        domain: second.userDeletionCoordinator.domain,
        userId: 'user-1',
        namespace: 'foreign',
      );

      await expectLater(
        first.userDeletionCoordinator.deleteUser('user-1', plans: [foreign]),
        throwsA(isA<AuthUserDeletionPreflightException>()),
      );
      expect(await first.users.findById('user-1'), isNotNull);
    });

    test('rejects missing and duplicate namespaces before mutation', () async {
      final backend = _Backend();
      final domain = AuthInMemoryUserDeletionDomain();
      final coordinator = AuthInMemoryUserDeletionCoordinator(
        domain: domain,
        backend: backend,
      );
      final firstStore = _PluginStore();
      final secondStore = _PluginStore();
      coordinator.bind([
        _Contributor(domain: domain, namespace: 'one', store: firstStore),
        _Contributor(domain: domain, namespace: 'two', store: secondStore),
      ]);

      await expectLater(
        coordinator.deleteUser(
          backend.user.id,
          plans: [
            AuthInMemoryUserDeletionPlan(
              domain: domain,
              userId: backend.user.id,
              namespace: 'one',
              operation: AuthInMemoryStoreDeletionOperation(
                store: firstStore,
                userId: backend.user.id,
              ),
            ),
          ],
        ),
        throwsA(isA<AuthUserDeletionPreflightException>()),
      );
      expect(backend.deleted, isFalse);
      expect(firstStore.records, contains(backend.user.id));

      await expectLater(
        coordinator.deleteUser(
          backend.user.id,
          plans: [
            for (final store in [firstStore, secondStore])
              AuthInMemoryUserDeletionPlan(
                domain: domain,
                userId: backend.user.id,
                namespace: 'one',
                operation: AuthInMemoryStoreDeletionOperation(
                  store: store,
                  userId: backend.user.id,
                ),
              ),
          ],
        ),
        throwsA(isA<AuthUserDeletionPreflightException>()),
      );
      expect(backend.deleted, isFalse);
    });

    test(
      'rolls plugin and token state back when core deletion faults',
      () async {
        final backend = _Backend(throwOnDelete: true);
        final domain = AuthInMemoryUserDeletionDomain();
        final pluginStore = _PluginStore();
        final coordinator = AuthInMemoryUserDeletionCoordinator(
          domain: domain,
          backend: backend,
        );
        coordinator.bind([
          _Contributor(domain: domain, namespace: 'plugin', store: pluginStore),
        ]);

        await expectLater(
          coordinator.confirmAndDeleteUser(
            userId: backend.user.id,
            token: 'valid-token',
          ),
          throwsStateError,
        );
        expect(backend.deleted, isFalse);
        expect(backend.tokenAvailable, isTrue);
        expect(pluginStore.records, contains(backend.user.id));
      },
    );

    test('serializes token contention to one deletion winner', () async {
      final backend = _Backend();
      final domain = AuthInMemoryUserDeletionDomain();
      final coordinator = AuthInMemoryUserDeletionCoordinator(
        domain: domain,
        backend: backend,
      )..bind(const []);

      final results = await Future.wait([
        for (var index = 0; index < 16; index++)
          coordinator.confirmAndDeleteUser(
            userId: backend.user.id,
            token: 'valid-token',
          ),
      ]);

      expect(results.where((value) => value), hasLength(1));
      expect(backend.deleteAttempts, 1);
    });
  });
}

final class _Backend implements AuthInMemoryUserDeletionBackend {
  _Backend({this.throwOnDelete = false});

  final bool throwOnDelete;
  final AuthUser user = AuthUser(id: 'user-1');
  bool tokenAvailable = true;
  bool deleted = false;
  int deleteAttempts = 0;

  @override
  Object captureDeletionState() => (
    tokenAvailable: tokenAvailable,
    deleted: deleted,
    deleteAttempts: deleteAttempts,
  );

  @override
  bool consumeUserDeletionToken(String userId, String token) {
    if (deleted || !tokenAvailable || token != 'valid-token') return false;
    tokenAvailable = false;
    return true;
  }

  @override
  bool deleteCoreUserData(String userId) {
    deleteAttempts++;
    if (throwOnDelete) throw StateError('injected core deletion fault');
    if (deleted) return false;
    deleted = true;
    return true;
  }

  @override
  AuthUser? findUserForDeletion(String userId) => deleted ? null : user;

  @override
  void restoreDeletionState(Object state) {
    final value =
        state as ({bool tokenAvailable, bool deleted, int deleteAttempts});
    tokenAvailable = value.tokenAvailable;
    deleted = value.deleted;
    deleteAttempts = value.deleteAttempts;
  }

  @override
  void validateUserDeletion(String userId) {}
}

final class _PluginStore implements AuthInMemoryUserDeletionStore {
  final Set<String> records = {'user-1'};

  @override
  Object captureDeletionState() => Set<String>.of(records);

  @override
  void deleteUserDataForDeletion(String userId) {
    records.remove(userId);
  }

  @override
  void restoreDeletionState(Object state) {
    records
      ..clear()
      ..addAll(state as Set<String>);
  }
}

final class _Contributor implements AuthUserDeletionPlanContributor {
  const _Contributor({
    required this.domain,
    required this.namespace,
    required this.store,
  });

  final AuthInMemoryUserDeletionDomain domain;
  final String namespace;
  final AuthInMemoryUserDeletionStore store;

  @override
  String get userDataNamespace => namespace;

  @override
  AuthUserDeletionPlan createUserDeletionPlan(AuthUser user) =>
      AuthInMemoryUserDeletionPlan(
        domain: domain,
        userId: user.id,
        namespace: namespace,
        operation: AuthInMemoryStoreDeletionOperation(
          store: store,
          userId: user.id,
        ),
      );
}
