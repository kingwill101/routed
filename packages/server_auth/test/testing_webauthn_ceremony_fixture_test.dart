import 'package:server_auth/testing.dart';
import 'package:test/test.dart';

void main() {
  group('AuthWebAuthnCeremonyFixture', () {
    test(
      'emits browser registration JSON and deterministic DER assertions',
      () {
        final fixture = AuthWebAuthnCeremonyFixture(
          relyingPartyId: 'example.test',
          origin: Uri.parse('https://example.test'),
        );

        final registration = fixture.registrationCredential(
          challenge: 'registration-challenge',
        );
        expect(registration['id'], fixture.credentialId);
        expect(registration['rawId'], fixture.credentialId);
        expect(registration['type'], 'public-key');
        expect(registration['authenticatorAttachment'], 'platform');
        expect(registration['clientExtensionResults'], isEmpty);
        expect(
          (registration['response'] as Map)['transports'],
          equals(<String>['internal']),
        );

        final first = fixture.assertionCredential(
          challenge: 'authentication-challenge',
          counter: 1,
          userHandle: 'browser-user-handle',
        );
        final second = fixture.assertionCredential(
          challenge: 'authentication-challenge',
          counter: 1,
          userHandle: 'browser-user-handle',
        );
        expect(fixture.hasDerEs256Signature(first), isTrue);
        expect(
          (first['response'] as Map)['signature'],
          (second['response'] as Map)['signature'],
        );
        expect((first['response'] as Map)['userHandle'], 'browser-user-handle');
      },
    );

    test('rejects malformed assertion signature framing', () {
      final fixture = AuthWebAuthnCeremonyFixture(
        relyingPartyId: 'example.test',
        origin: Uri.parse('https://example.test'),
      );

      expect(
        fixture.hasDerEs256Signature(<String, dynamic>{
          'response': <String, dynamic>{'signature': 'bm90LWRlcg'},
        }),
        isFalse,
      );
    });
  });
}
