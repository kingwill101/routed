import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  final suite = AuthPhoneNumberBackendConformanceSuite(() {
    final faults = _FaultController();
    final store = InMemoryAuthStore(
      phoneNumberFaultInjector: (point) {
        final conformancePoint =
            point == AuthPhoneNumberInMemoryFaultPoint.issueAfterChallengeWrite
            ? AuthPhoneNumberBackendConformanceFaultPoint.issue
            : AuthPhoneNumberBackendConformanceFaultPoint.verify;
        faults.inject(conformancePoint);
      },
    );
    store.bindUserDeletionPlanContributors(const []);
    return AuthPhoneNumberBackendConformanceFixture(
      store: store,
      backend: store,
      faults: faults,
      hardDeleteUser: store.userDeletionCoordinator.deleteUser,
    );
  });

  for (final conformanceCase in suite.cases) {
    test(conformanceCase.id, conformanceCase.run);
  }
}

final class _FaultController
    implements AuthPhoneNumberBackendConformanceFaultController {
  AuthPhoneNumberBackendConformanceFaultPoint? _next;

  @override
  void failNext(AuthPhoneNumberBackendConformanceFaultPoint point) {
    if (_next != null) throw StateError('a fault is already armed');
    _next = point;
  }

  void inject(AuthPhoneNumberBackendConformanceFaultPoint point) {
    if (_next != point) return;
    _next = null;
    throw StateError('injected $point');
  }
}
