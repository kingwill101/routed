import 'dart:async';

import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  final suite = AuthAnonymousStoreConformanceSuite(() {
    final faults = _FaultController();
    final store = InMemoryAuthStore(
      anonymousFaultInjector: (point) {
        if (point == AuthAnonymousInMemoryFaultPoint.afterCreateWrite &&
            faults.consumeCreate()) {
          throw StateError('injected anonymous create failure');
        }
      },
      userDeletionFaultInjector: (point) {
        if (point == AuthUserDeletionFaultPoint.core &&
            faults.consumeDeletion()) {
          throw StateError('injected anonymous deletion failure');
        }
      },
    );
    AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: const [],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        plugins: [AnonymousPlugin<Object>()],
      ),
    );
    return AuthAnonymousStoreConformanceFixture(
      store: store,
      mutations: store,
      faults: faults,
    );
  });

  for (final conformanceCase in suite.cases) {
    test(conformanceCase.description, conformanceCase.run);
  }

  test('publishes stable unique case identifiers', () {
    expect(
      suite.cases.map((conformanceCase) => conformanceCase.id),
      orderedEquals(const <String>[
        'create_replay',
        'create_contention',
        'create_rollback',
        'delete_contention',
        'delete_rollback',
        'hard_delete_scrubs_create_replay',
        'upgrade_replay',
        'upgrade_rollback',
        'upgrade_target_binding',
      ]),
    );
  });

  test(
    'concurrent hard deletion cannot leave a creation replay receipt',
    () async {
      final reachedWrite = Completer<void>();
      final resumeCreate = Completer<void>();
      final store = InMemoryAuthStore(
        anonymousFaultInjector: (point) async {
          if (point != AuthAnonymousInMemoryFaultPoint.afterCreateWrite) return;
          reachedWrite.complete();
          await resumeCreate.future;
        },
      );
      AuthRuntime<Object>(
        options: AuthOptions<Object>(
          providers: const [],
          store: store,
          storeMode: AuthStoreMode.ephemeral,
          plugins: [AnonymousPlugin<Object>()],
        ),
      );
      final command = AuthAnonymousCreateAccountCommand(
        operationId: 'concurrent-hard-delete-create',
        user: AuthUser(id: 'concurrent-hard-delete-user', isAnonymous: true),
      );

      final creation = store.createAnonymousAccount(command);
      await reachedWrite.future;
      expect(
        await store.userDeletionCoordinator.deleteUser(command.user.id),
        isTrue,
      );
      resumeCreate.complete();

      await expectLater(creation, throwsStateError);
      expect(await store.users.findById(command.user.id), isNull);
      await expectLater(
        store.createAnonymousAccount(command),
        throwsStateError,
      );
    },
  );
}

final class _FaultController
    implements AuthAnonymousStoreConformanceFaultController {
  bool _create = false;
  bool _deletion = false;

  @override
  void failNext(AuthAnonymousStoreConformanceFaultPoint point) {
    switch (point) {
      case AuthAnonymousStoreConformanceFaultPoint.afterCreateWrite:
        _create = true;
      case AuthAnonymousStoreConformanceFaultPoint.duringDelete:
      case AuthAnonymousStoreConformanceFaultPoint.duringUpgrade:
        _deletion = true;
    }
  }

  bool consumeCreate() {
    final value = _create;
    _create = false;
    return value;
  }

  bool consumeDeletion() {
    final value = _deletion;
    _deletion = false;
    return value;
  }
}
