import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  final suite = AuthScimApplicationProjectionStoreConformanceSuite(() {
    final faults = _FaultController();
    final store = InMemoryAuthScimApplicationProjectionStore(
      clock: () => DateTime.utc(2030),
      faultInjector: (point) {
        final conformancePoint = switch (point) {
          AuthScimApplicationProjectionFaultPoint.afterProjectionWrite =>
            AuthScimApplicationProjectionStoreConformanceFaultPoint.apply,
          AuthScimApplicationProjectionFaultPoint.duringReconciliation =>
            AuthScimApplicationProjectionStoreConformanceFaultPoint.reconcile,
          AuthScimApplicationProjectionFaultPoint.duringScopeDeletion =>
            AuthScimApplicationProjectionStoreConformanceFaultPoint.deleteScope,
        };
        if (faults.consume(conformancePoint)) {
          throw StateError('injected SCIM projection failure');
        }
      },
    );
    return AuthScimApplicationProjectionStoreConformanceFixture(
      store: store,
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
        'apply_replay_binding',
        'scope_resource_isolation',
        'optimistic_version',
        'resource_tombstone_final',
        'membership_integrity',
        'apply_rollback',
        'apply_contention',
        'drift_classification',
        'reconcile_atomic',
        'reconcile_replay_stale',
        'reconcile_rollback',
        'scope_delete_fence',
        'scope_delete_rollback',
        'bounded_catalog',
      ]),
    );
  });
}

final class _FaultController
    implements AuthScimApplicationProjectionStoreConformanceFaultController {
  final Set<AuthScimApplicationProjectionStoreConformanceFaultPoint> _armed =
      <AuthScimApplicationProjectionStoreConformanceFaultPoint>{};

  @override
  void failNext(AuthScimApplicationProjectionStoreConformanceFaultPoint point) {
    _armed.add(point);
  }

  bool consume(AuthScimApplicationProjectionStoreConformanceFaultPoint point) =>
      _armed.remove(point);
}
