import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  final suite = AuthAdminStoreConformanceSuite(
    createFixture: () {
      final core = InMemoryAuthStore();
      final faultControl = _FaultControl();
      final store = InMemoryAuthAdminStore(
        core,
        faultInjector: (point, mutation) {
          if (faultControl.consume(point)) {
            throw StateError('injected transaction failure');
          }
        },
      );
      return AuthAdminStoreConformanceFixture(
        coreStore: core,
        adminStore: store,
        faultControl: faultControl,
      );
    },
  );

  for (final conformanceCase in suite.cases) {
    test(conformanceCase.description, () async {
      final result = await conformanceCase.run();
      if (result.isSkipped) markTestSkipped(result.skippedReason!);
    });
  }
}

final class _FaultControl implements AuthAdminStoreConformanceFaultControl {
  AuthAdminStoreConformanceFaultPoint? _next;

  @override
  void failNext(AuthAdminStoreConformanceFaultPoint point) {
    _next = point;
  }

  bool consume(AuthAdminInMemoryFaultPoint point) {
    final expected = switch (point) {
      AuthAdminInMemoryFaultPoint.afterMutation =>
        AuthAdminStoreConformanceFaultPoint.afterMutation,
    };
    if (_next != expected) return false;
    _next = null;
    return true;
  }
}
