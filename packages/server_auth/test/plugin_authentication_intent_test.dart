import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('AuthEndpointAuthenticationIntent', () {
    test(
      'projects only the host-owned public session representation',
      () async {
        final intent = AuthEndpointAuthenticationIntent(
          user: AuthUser(id: 'user-1'),
          authenticationMethod: 'test',
          metadata: const <String, dynamic>{'status': 'authenticated'},
        );
        final response = await intent.projectResponse(<String, dynamic>{
          'user': AuthUser(id: 'user-1').toJson(),
          'expires': null,
          'strategy': 'jwt',
        });

        expect(response, <String, dynamic>{
          'status': 'authenticated',
          'user': AuthUser(id: 'user-1').toJson(),
          'expires': null,
          'strategy': 'jwt',
        });
        expect(response.toString(), isNot(contains('token')));
      },
    );

    test(
      'property: plugin metadata cannot shadow host session fields',
      () async {
        final runner = PropertyTestRunner<String>(
          Chaos.string(minLength: 0, maxLength: 512),
          (value) {
            for (final key in const <String>[
              'user',
              'expires',
              'strategy',
              'token',
            ]) {
              expect(
                () => AuthEndpointAuthenticationIntent(
                  user: AuthUser(id: 'user-1'),
                  authenticationMethod: 'test',
                  metadata: <String, dynamic>{key: value},
                ),
                throwsArgumentError,
              );
            }
          },
          PropertyConfig(numTests: 300, seed: 20260820),
        );

        final result = await runner.run();
        expect(result.success, isTrue, reason: _propertyReport(result));
      },
    );
  });
}

String _propertyReport(PropertyResult result) {
  if (result.success) return 'All ${result.numTests} generated cases passed';
  return <Object?>[
    'Property failed after ${result.numTests} cases',
    'Original input: ${result.originalFailingInput}',
    'Shrunk input: ${result.failingInput}',
    'Shrinks: ${result.numShrinks}',
    'Error: ${result.error}',
    'Seed: ${result.seed}',
  ].join('\n');
}
