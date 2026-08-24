import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

const _sensitiveNames = <String>{
  'apikey',
  'authorization',
  'clientsecret',
  'credential',
  'credentials',
  'password',
  'passwordhash',
  'privatekey',
  'refreshtoken',
  'secret',
  'token',
  'accesstoken',
  'idtoken',
  'sessiontoken',
  'jwt',
  'csrftoken',
  'sessionid',
  'sessionkey',
  'passwordresettoken',
  'oauthaccesstoken',
  'secretvalue',
};

String _normalizeName(Object? name) =>
    name.toString().toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

Generator<Object?> _leafValue() {
  return Gen.frequency<Object?>([
    (4, Chaos.string(minLength: 0, maxLength: 200)),
    (2, Gen.integer(min: -100000, max: 100000)),
    (1, Gen.boolean()),
    (1, Gen.constant<Object?>(null)),
  ]);
}

Generator<String> _sensitiveName() {
  return Gen.oneOf(<String>[
    'password',
    'PASSWORD',
    'password_hash',
    'passwordHash',
    'passphrase',
    'passwd',
    'access_token',
    'access-token',
    'accessToken',
    'refresh_token',
    'refresh-token',
    'refreshToken',
    'id_token',
    'idToken',
    'session_token',
    'sessionToken',
    'api_key',
    'apiKey',
    'client_secret',
    'clientSecret',
    'private_key',
    'privateKey',
    'authorization',
    'secret',
    'token',
    'passwordResetToken',
    'oauthAccessToken',
    'jwt',
    'csrfToken',
    'sessionId',
    'sessionKey',
    'secretValue',
  ]);
}

Generator<Object?> _nestedValue(int depth) {
  if (depth >= 2) return _leafValue();

  return Gen.frequency<Object?>([
    (4, _leafValue()),
    (2, _generatedAttributes(depth + 1).map<Object?>((value) => value)),
    (
      2,
      _nestedValue(
        depth + 1,
      ).list(minLength: 1, maxLength: 3).map<Object?>((value) => value),
    ),
  ]);
}

Generator<Map<String, dynamic>> _generatedAttributes([int depth = 0]) {
  return _sensitiveName().flatMap((sensitiveName) {
    return _nestedValue(depth).flatMap((sensitiveValue) {
      return _leafValue().map((safeValue) {
        return <String, dynamic>{
          sensitiveName: sensitiveValue,
          'publicField': safeValue,
          'nested': <String, dynamic>{
            sensitiveName: 'nested-secret',
            'publicNested': 'safe',
          },
        };
      });
    });
  });
}

void _expectNoSensitiveKeys(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      expect(
        _sensitiveNames.contains(_normalizeName(entry.key)),
        isFalse,
        reason: 'Sensitive key survived serialization: ${entry.key}',
      );
      _expectNoSensitiveKeys(entry.value);
    }
  } else if (value is Iterable) {
    for (final item in value) {
      _expectNoSensitiveKeys(item);
    }
  }
}

String _propertyReport(PropertyResult result) {
  if (result.success) return 'All ${result.numTests} generated cases passed';
  return [
    'Property failed after ${result.numTests} cases',
    'Original input: ${result.originalFailingInput}',
    'Shrunk input: ${result.failingInput}',
    'Shrinks: ${result.numShrinks}',
    'Error: ${result.error}',
    'Seed: ${result.seed}',
  ].join('\n');
}

void main() {
  test(
    'public auth serialization redacts hostile credential key shapes',
    () async {
      final runner = PropertyTestRunner<Map<String, dynamic>>(
        _generatedAttributes(),
        (attributes) {
          final userAttributes = AuthUser(
            id: 'user-1',
            attributes: attributes,
          ).toJson()['attributes'];
          final principalAttributes = AuthPrincipal(
            id: 'user-1',
            attributes: attributes,
          ).toJson()['attributes'];
          final accountMetadata = AuthAccount(
            providerId: 'provider',
            providerAccountId: 'account-1',
            metadata: attributes,
          ).toJson()['metadata'];
          final redactedCredentials = AuthCredentials(
            password: 'password-secret',
            attributes: attributes,
          ).redacted().attributes;
          final restoredUser = AuthUser.fromJson({
            'id': 'user-1',
            'roles': <Object?>['admin', 42, null],
            'attributes': attributes,
          });

          for (final projection in <Object?>[
            userAttributes,
            principalAttributes,
            accountMetadata,
            redactedCredentials,
            restoredUser.attributes,
          ]) {
            _expectNoSensitiveKeys(projection);
            expect(
              (projection! as Map)['publicField'],
              equals(attributes['publicField']),
            );
          }
          expect(restoredUser.roles, equals(['admin']));
        },
        PropertyConfig(numTests: 500, seed: 20260818),
      );

      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    },
  );
}
