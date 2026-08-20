import 'package:routed_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  group('auth runtime conformance test support', () {
    test('response header lookup is case insensitive', () {
      const response = AuthRuntimeConformanceResponse(
        statusCode: 200,
        headers: <String, List<String>>{
          'Set-Cookie': <String>['first=one'],
          'set-cookie': <String>['second=two'],
        },
        body: '{}',
      );

      expect(
        response.headerValues('SET-COOKIE'),
        equals(<String>['first=one', 'second=two']),
      );
      expect(response.json, isA<Map<String, Object?>>());
    });

    test('reports a stable case identifier without package:test coupling', () {
      expect(
        () => verifyAuthRuntimeConformance(
          origin: Uri.parse('https://runtime.example'),
          send: (_) async => const AuthRuntimeConformanceResponse(
            statusCode: 503,
            headers: <String, List<String>>{},
            body: 'unavailable',
          ),
        ),
        throwsA(
          isA<AuthRuntimeConformanceFailure>()
              .having((failure) => failure.caseId, 'caseId', 'csrf.issue')
              .having((failure) => failure.message, 'message', contains('503')),
        ),
      );
    });
  });
}
