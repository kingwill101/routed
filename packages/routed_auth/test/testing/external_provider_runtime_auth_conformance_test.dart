import 'package:routed_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  test('external-provider support reports a stable flow identifier', () {
    expect(
      () => verifyAuthExternalProviderRuntimeConformance(
        origin: Uri.parse('https://runtime.example'),
        send: (_) async => const AuthRuntimeConformanceResponse(
          statusCode: 503,
          headers: <String, List<String>>{},
          body: 'unavailable',
        ),
        expectJwt: false,
      ),
      throwsA(
        isA<AuthRuntimeConformanceFailure>()
            .having((failure) => failure.caseId, 'caseId', 'external.seed-user')
            .having((failure) => failure.message, 'message', contains('503')),
      ),
    );
  });
}
