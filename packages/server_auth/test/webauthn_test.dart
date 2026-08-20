import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart' as cbor;
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

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

final class _Fixture {
  _Fixture({
    WebAuthnRegistrationOptions? registrationOptions,
    WebAuthnAttestationTrustPolicy attestationTrustPolicy =
        const WebAuthnAttestationTrustPolicy.passkeys(),
  }) {
    provider = WebAuthnProvider(
      getUserInfo: (_, _, _) => null,
      getRelyingParty: (_, _) => const WebAuthnRelyingParty(
        id: 'example.com',
        name: 'Example',
        origin: 'https://example.com',
      ),
      registrationOptions:
          registrationOptions ?? const WebAuthnRegistrationOptions(),
    );
    store = InMemoryAuthStore();
    user = AuthUser(
      id: 'user-1',
      email: 'user@example.com',
      name: 'Example User',
    );
    feature = WebAuthnPlugin<Object>(
      provider: provider,
      attestationTrustPolicy: attestationTrustPolicy,
    );
    AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: [provider],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        plugins: [feature],
      ),
    );
  }

  late final WebAuthnProvider provider;
  late final InMemoryAuthStore store;
  late final AuthUser user;
  late final WebAuthnPlugin<Object> feature;
  final Object context = Object();
  final _KeyPair keyPair = _KeyPair.create();
}

final class _RecordingSessionControl implements AuthServerPluginSessionControl {
  AuthUser? replacedUser;
  String? authenticationMethod;

  @override
  AuthSessionStrategy get strategy => AuthSessionStrategy.session;

  @override
  String? get currentSessionId => null;

  @override
  Future<AuthSession> replaceIdentity(
    AuthUser user, {
    required String authenticationMethod,
    Duration? maximumAge,
    String? impersonatedBy,
  }) async {
    replacedUser = user;
    this.authenticationMethod = authenticationMethod;
    return AuthSession(
      user: user,
      expiresAt: DateTime.utc(2030, 1, 1),
      strategy: AuthSessionStrategy.session,
    );
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  group('WebAuthn stores', () {
    test('challenge consumption is bound and one-time', () async {
      final store = InMemoryAuthWebAuthnChallengeStore();
      final created = DateTime.utc(2030, 1, 1);
      final challenge = AuthWebAuthnChallenge(
        id: 'challenge-1',
        challengeHash: 'hash-1',
        ceremony: AuthWebAuthnCeremony.authentication,
        relyingPartyId: 'example.com',
        origin: 'https://example.com',
        createdAt: created,
        expiresAt: created.add(const Duration(minutes: 5)),
        userId: 'user-1',
      );
      await store.save(challenge);

      expect(
        await store.consume(
          challengeHash: 'hash-1',
          ceremony: AuthWebAuthnCeremony.authentication,
          relyingPartyId: 'example.com',
          origin: 'https://evil.example',
          userId: 'user-1',
          now: created,
        ),
        isNull,
      );
      expect(
        await store.consume(
          challengeHash: 'hash-1',
          ceremony: AuthWebAuthnCeremony.authentication,
          relyingPartyId: 'example.com',
          origin: 'https://example.com',
          userId: 'user-1',
          now: created,
        ),
        same(challenge),
      );
      expect(
        await store.consume(
          challengeHash: 'hash-1',
          ceremony: AuthWebAuthnCeremony.authentication,
          relyingPartyId: 'example.com',
          origin: 'https://example.com',
          userId: 'user-1',
          now: created,
        ),
        isNull,
      );
    });

    test('counter writes use compare-and-set semantics', () async {
      final store = InMemoryAuthWebAuthnAuthenticatorStore();
      final created = DateTime.utc(2030, 1, 1);
      await store.create(
        WebAuthnAuthenticator(
          credentialId: 'credential-1',
          publicKey: 'cose-key',
          counter: 4,
          userId: 'user-1',
          createdAt: created,
        ),
      );

      expect(
        await store.updateUsage(
          credentialId: 'credential-1',
          expectedCounter: 3,
          newCounter: 5,
          lastUsedAt: created.add(const Duration(minutes: 1)),
        ),
        isNull,
      );
      final updated = await store.updateUsage(
        credentialId: 'credential-1',
        expectedCounter: 4,
        newCounter: 5,
        lastUsedAt: created.add(const Duration(minutes: 1)),
      );
      expect(updated?.counter, 5);
      expect(
        await store.updateUsage(
          credentialId: 'credential-1',
          expectedCounter: 4,
          newCounter: 6,
          lastUsedAt: created.add(const Duration(minutes: 2)),
        ),
        isNull,
      );
    });

    test(
      'renames only the owning credential and preserves ceremony state',
      () async {
        final store = InMemoryAuthWebAuthnAuthenticatorStore();
        final created = DateTime.utc(2030, 1, 1);
        final authenticator = WebAuthnAuthenticator(
          credentialId: 'credential-1',
          publicKey: 'cose-key',
          counter: 4,
          userId: 'user-1',
          transports: ['internal'],
          createdAt: created,
          lastUsedAt: created.add(const Duration(minutes: 1)),
          name: 'Old name',
        );
        await store.create(authenticator);

        final renamed = await store.renameForUser(
          'user-1',
          'credential-1',
          '  New name  ',
        );
        expect(renamed?.name, 'New name');
        expect(renamed?.credentialId, authenticator.credentialId);
        expect(renamed?.publicKey, authenticator.publicKey);
        expect(renamed?.counter, authenticator.counter);
        expect(renamed?.transports, authenticator.transports);
        expect(
          await store.renameForUser('other-user', 'credential-1', 'Hijack'),
          isNull,
        );
        expect(
          await store.renameForUser('user-1', 'credential-1', '   '),
          isNull,
        );
      },
    );
  });

  group('WebAuthn ceremonies', () {
    test(
      'registers an ES256 passkey and authenticates a browser DER signature',
      () async {
        final fixture = _Fixture();
        await fixture.store.users.create(fixture.user);
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final registrationResponse = _registrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
        );

        final saved = await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: registrationResponse,
        );
        expect(saved.userId, fixture.user.id);
        expect(saved.counter, 0);
        expect(saved.credentialId, isNotEmpty);

        final authentication = await fixture.feature.beginAuthentication(
          context: fixture.context,
          userId: fixture.user.id,
        );
        expect(authentication.allowCredentials, contains(saved.credentialId));
        final assertion = _assertionCredential(
          challenge: authentication.challenge,
          credentialId: saved.credentialId,
          keyPair: fixture.keyPair,
          counter: 1,
        );
        final result = await fixture.feature.finishAuthentication(
          context: fixture.context,
          credential: assertion,
          userId: fixture.user.id,
        );
        expect(result.user.id, fixture.user.id);
        expect(result.authenticator.counter, 1);
      },
    );

    test('registers and authenticates an Ed25519 passkey', () async {
      final fixture = _Fixture();
      final keyPair = await _Ed25519KeyPair.create();
      await fixture.store.users.create(fixture.user);
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );
      final credentialParameters =
          registration.toJson()['pubKeyCredParams']! as List<dynamic>;
      expect(
        credentialParameters.first,
        equals(<String, dynamic>{'type': 'public-key', 'alg': -8}),
      );

      final saved = await fixture.feature.finishRegistration(
        context: fixture.context,
        user: fixture.user,
        credential: await _ed25519RegistrationCredential(
          challenge: registration.challenge,
          keyPair: keyPair,
        ),
      );

      final authentication = await fixture.feature.beginAuthentication(
        context: fixture.context,
        userId: fixture.user.id,
      );
      final result = await fixture.feature.finishAuthentication(
        context: fixture.context,
        credential: await _ed25519AssertionCredential(
          challenge: authentication.challenge,
          credentialId: saved.credentialId,
          keyPair: keyPair,
          counter: 1,
        ),
        userId: fixture.user.id,
      );

      expect(result.user.id, fixture.user.id);
      expect(result.authenticator.counter, 1);
    });

    test('registers packed Ed25519 self-attestation', () async {
      final fixture = _Fixture();
      final keyPair = await _Ed25519KeyPair.create();
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );

      final saved = await fixture.feature.finishRegistration(
        context: fixture.context,
        user: fixture.user,
        credential: await _ed25519RegistrationCredential(
          challenge: registration.challenge,
          keyPair: keyPair,
          attestationFormat: 'packed',
        ),
      );

      expect(saved.publicKey, isNotEmpty);
    });

    test('rejects malformed Ed25519 COSE keys', () async {
      final keyPair = await _Ed25519KeyPair.create();
      final malformedKeys = <List<int>>[
        cbor.cbor.encode(<Object?, Object?>{
          1: 2,
          3: -8,
          -1: 6,
          -2: keyPair.publicKey,
        }),
        cbor.cbor.encode(<Object?, Object?>{
          1: 1,
          3: -8,
          -1: 7,
          -2: keyPair.publicKey,
        }),
        cbor.cbor.encode(<Object?, Object?>{
          1: 1.0,
          3: -8,
          -1: 6,
          -2: keyPair.publicKey,
        }),
        cbor.cbor.encode(<Object?, Object?>{
          1: 1,
          3: -8.0,
          -1: 6,
          -2: keyPair.publicKey,
        }),
        cbor.cbor.encode(<Object?, Object?>{
          1: 1,
          3: -8,
          -1: 6,
          -2: keyPair.publicKey.sublist(1),
        }),
        cbor.cbor.encode(<Object?, Object?>{
          1: 1,
          3: -8,
          -1: 6,
          -2: 'not-key-bytes',
        }),
      ];

      for (final coseKey in malformedKeys) {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final credential = await _ed25519RegistrationCredential(
          challenge: registration.challenge,
          keyPair: keyPair,
          cosePublicKey: coseKey,
        );
        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: credential,
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              anyOf(
                'webauthn_public_key_invalid',
                'webauthn_public_key_unsupported',
              ),
            ),
          ),
        );
      }
    });

    test(
      'rejects malformed and forged Ed25519 assertions generically',
      () async {
        final fixture = _Fixture();
        final keyPair = await _Ed25519KeyPair.create();
        await fixture.store.users.create(fixture.user);
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final saved = await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: await _ed25519RegistrationCredential(
            challenge: registration.challenge,
            keyPair: keyPair,
          ),
        );

        for (final signature in <List<int>>[
          List<int>.filled(63, 0),
          List<int>.filled(65, 0),
          List<int>.filled(64, 0),
        ]) {
          final authentication = await fixture.feature.beginAuthentication(
            context: fixture.context,
            userId: fixture.user.id,
          );
          final assertion = await _ed25519AssertionCredential(
            challenge: authentication.challenge,
            credentialId: saved.credentialId,
            keyPair: keyPair,
            counter: 1,
          );
          (assertion['response']! as Map<String, dynamic>)['signature'] =
              base64UrlNoPadding(signature);

          await expectLater(
            () => fixture.feature.finishAuthentication(
              context: fixture.context,
              credential: assertion,
              userId: fixture.user.id,
            ),
            throwsA(
              isA<AuthFlowException>().having(
                (error) => error.code,
                'code',
                'webauthn_signature_invalid',
              ),
            ),
          );
        }
      },
    );

    test(
      'registers and authenticates a browser-shaped FIDO U2F attestation',
      () async {
        final fixture = _Fixture();
        await fixture.store.users.create(fixture.user);
        final attestationKey = _KeyPair.create(privateValue: BigInt.two);
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final saved = await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _u2fRegistrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
            attestationKey: attestationKey,
          ),
        );

        expect(saved.publicKey, isNotEmpty);
        expect(saved.counter, 0);

        final authentication = await fixture.feature.beginAuthentication(
          context: fixture.context,
          userId: fixture.user.id,
        );
        final result = await fixture.feature.finishAuthentication(
          context: fixture.context,
          credential: _assertionCredential(
            challenge: authentication.challenge,
            credentialId: saved.credentialId,
            keyPair: fixture.keyPair,
            counter: 1,
          ),
          userId: fixture.user.id,
        );
        expect(result.user.id, fixture.user.id);
        expect(result.authenticator.counter, 1);
      },
    );

    test(
      'rejects a FIDO U2F signature with non-exact verification data',
      () async {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );

        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: _u2fRegistrationCredential(
              challenge: registration.challenge,
              keyPair: fixture.keyPair,
              wrongVerificationData: true,
            ),
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'webauthn_attestation_invalid',
            ),
          ),
        );
      },
    );

    test(
      'rejects a FIDO U2F credential ID that is not bound to authData',
      () async {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final credential = _u2fRegistrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
        );
        final mismatchedId = base64UrlNoPadding(
          Uint8List.fromList(List<int>.filled(16, 0xff)),
        );
        credential['id'] = mismatchedId;
        credential['rawId'] = mismatchedId;

        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: credential,
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'webauthn_credential_invalid',
            ),
          ),
        );
      },
    );

    test('rejects malformed FIDO U2F COSE EC2 coordinates', () async {
      final fixture = _Fixture();
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );
      final malformedCoseKey = cbor.cbor.encode(<Object?, Object?>{
        1: 2,
        3: -7,
        -1: 1,
        -2: List<int>.filled(31, 0),
        -3: List<int>.filled(32, 0),
      });

      await expectLater(
        () => fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _u2fRegistrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
            cosePublicKey: malformedCoseKey,
          ),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'webauthn_public_key_invalid',
          ),
        ),
      );
    });

    test(
      'rejects FIDO U2F statements without exactly one bounded x5c leaf',
      () async {
        Future<void> expectInvalidCertificateChain(List<Object?> chain) async {
          final fixture = _Fixture();
          final registration = await fixture.feature.beginRegistration(
            context: fixture.context,
            user: fixture.user,
          );
          await expectLater(
            () => fixture.feature.finishRegistration(
              context: fixture.context,
              user: fixture.user,
              credential: _u2fRegistrationCredential(
                challenge: registration.challenge,
                keyPair: fixture.keyPair,
                certificateChain: chain,
              ),
            ),
            throwsA(
              isA<AuthFlowException>().having(
                (error) => error.code,
                'code',
                'webauthn_attestation_invalid',
              ),
            ),
          );
        }

        final validCertificate = _packedAttestationCertificate(
          _KeyPair.create(privateValue: BigInt.two),
        );
        await expectInvalidCertificateChain(const <Object?>[]);
        await expectInvalidCertificateChain(<Object?>[
          validCertificate,
          validCertificate,
        ]);
        await expectInvalidCertificateChain(<Object?>[
          List<int>.filled(16385, 0),
        ]);
        final rsaKeyPair = _RsaKeyPair.create();
        await expectInvalidCertificateChain(<Object?>[
          _packedRsaAttestationCertificate(rsaKeyPair),
        ]);
      },
    );

    test(
      'rejects malformed FIDO U2F attestation CBOR with a stable error',
      () async {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final credential = _u2fRegistrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
        );
        final response =
            Map<String, dynamic>.from(credential['response']! as Map)
              ..['attestationObject'] = base64UrlNoPadding(
                Uint8List.fromList(<int>[0xa1, 0x01]),
              );
        credential['response'] = response;

        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: credential,
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'webauthn_attestation_invalid',
            ),
          ),
        );
      },
    );

    test('rejects malformed DER and raw FIDO U2F signatures', () async {
      final fixture = _Fixture();
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );
      final certificate = _packedAttestationCertificate(
        _KeyPair.create(privateValue: BigInt.two),
      );
      final malformedCertificate = <Object?>[
        <int>[...certificate, 0x00],
      ];

      await expectLater(
        () => fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _u2fRegistrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
            certificateChain: malformedCertificate,
          ),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'webauthn_attestation_invalid',
          ),
        ),
      );

      final secondFixture = _Fixture();
      final secondRegistration = await secondFixture.feature.beginRegistration(
        context: secondFixture.context,
        user: secondFixture.user,
      );
      await expectLater(
        () => secondFixture.feature.finishRegistration(
          context: secondFixture.context,
          user: secondFixture.user,
          credential: _u2fRegistrationCredential(
            challenge: secondRegistration.challenge,
            keyPair: secondFixture.keyPair,
            rawSignature: true,
          ),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'webauthn_attestation_invalid',
          ),
        ),
      );
    });

    test('registers a browser-shaped packed ES256 self-attestation', () async {
      final fixture = _Fixture(
        registrationOptions: const WebAuthnRegistrationOptions(
          attestation: 'direct',
        ),
      );
      await fixture.store.users.create(fixture.user);
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );

      expect(registration.attestation, 'direct');
      final saved = await fixture.feature.finishRegistration(
        context: fixture.context,
        user: fixture.user,
        credential: _registrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
          attestationFormat: 'packed',
        ),
      );

      expect(saved.userId, fixture.user.id);
      expect(saved.publicKey, isNotEmpty);
    });

    test('registers a browser-shaped packed RS256 self-attestation', () async {
      final fixture = _Fixture();
      final keyPair = _RsaKeyPair.create();
      await fixture.store.users.create(fixture.user);
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );

      final saved = await fixture.feature.finishRegistration(
        context: fixture.context,
        user: fixture.user,
        credential: _rsaRegistrationCredential(
          challenge: registration.challenge,
          keyPair: keyPair,
        ),
      );

      expect(saved.userId, fixture.user.id);
      expect(saved.publicKey, base64UrlNoPadding(keyPair.cosePublicKey));
    });

    test(
      'rejects a forged packed self-attestation without consuming challenge',
      () async {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final forged = _registrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
          attestationFormat: 'packed',
          corruptPackedSignature: true,
        );

        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: forged,
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'webauthn_attestation_invalid',
            ),
          ),
        );

        final saved = await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _registrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
            attestationFormat: 'packed',
          ),
        );
        expect(saved.credentialId, isNotEmpty);
      },
    );

    test('rejects packed attestation with a mismatched algorithm', () async {
      final fixture = _Fixture();
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );

      await expectLater(
        () => fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _registrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
            attestationFormat: 'packed',
            packedAlgorithm: -257,
          ),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'webauthn_attestation_invalid',
          ),
        ),
      );
    });

    test('registers certificate-backed packed ES256 attestation', () async {
      final fixture = _Fixture();
      final attestationKey = _KeyPair.create(privateValue: BigInt.two);
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );

      final saved = await fixture.feature.finishRegistration(
        context: fixture.context,
        user: fixture.user,
        credential: _registrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
          attestationFormat: 'packed',
          packedSigningKey: attestationKey,
          packedCertificateChain: <Object?>[
            _packedAttestationCertificate(attestationKey),
          ],
        ),
      );

      expect(saved.userId, fixture.user.id);
    });

    test(
      'accepts a certificate path ending at an explicit trusted root',
      () async {
        final attestationKey = _KeyPair.create(privateValue: BigInt.two);
        final certificate = _packedAttestationCertificate(attestationKey);
        final fixture = _Fixture(
          attestationTrustPolicy: WebAuthnAttestationTrustPolicy.trustedRoots(
            roots: <List<int>>[certificate],
          ),
        );
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );

        final saved = await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _registrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
            attestationFormat: 'packed',
            packedSigningKey: attestationKey,
            packedCertificateChain: <Object?>[certificate],
          ),
        );

        expect(saved.userId, fixture.user.id);
      },
    );

    test(
      'rejects an untrusted self-signed path with a generic error',
      () async {
        final trustedKey = _KeyPair.create(privateValue: BigInt.from(3));
        final untrustedKey = _KeyPair.create(privateValue: BigInt.two);
        final fixture = _Fixture(
          attestationTrustPolicy: WebAuthnAttestationTrustPolicy.trustedRoots(
            roots: <List<int>>[_packedAttestationCertificate(trustedKey)],
          ),
        );
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );

        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: _registrationCredential(
              challenge: registration.challenge,
              keyPair: fixture.keyPair,
              attestationFormat: 'packed',
              packedSigningKey: untrustedKey,
              packedCertificateChain: <Object?>[
                _packedAttestationCertificate(untrustedKey),
              ],
            ),
          ),
          throwsA(
            isA<AuthFlowException>()
                .having(
                  (error) => error.code,
                  'code',
                  'webauthn_attestation_untrusted',
                )
                .having(
                  (error) => error.toString(),
                  'public representation',
                  'AuthFlowException(webauthn_attestation_untrusted)',
                ),
          ),
        );
      },
    );

    test('policy rejection does not consume a valid challenge', () async {
      var reject = true;
      WebAuthnAttestationMetadata? observed;
      final fixture = _Fixture(
        attestationTrustPolicy: WebAuthnAttestationTrustPolicy(
          evaluateCertificate: (metadata) {
            observed = metadata;
            return reject
                ? WebAuthnAttestationTrustDecision.reject
                : WebAuthnAttestationTrustDecision.accept;
          },
        ),
      );
      final attestationKey = _KeyPair.create(privateValue: BigInt.two);
      final certificate = _packedAttestationCertificate(attestationKey);
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );
      final credential = _registrationCredential(
        challenge: registration.challenge,
        keyPair: fixture.keyPair,
        attestationFormat: 'packed',
        packedSigningKey: attestationKey,
        packedCertificateChain: <Object?>[certificate],
      );

      await expectLater(
        () => fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: credential,
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'webauthn_attestation_untrusted',
          ),
        ),
      );
      expect(observed?.format, 'packed');
      expect(observed?.kind, WebAuthnAttestationKind.certificate);
      expect(observed?.aaguid, '00000000-0000-0000-0000-000000000000');
      expect(observed?.certificateTrustPath, hasLength(1));
      expect(
        observed?.certificateTrustPath.single.sha256Fingerprint,
        crypto.sha256.convert(certificate).toString(),
      );
      expect(
        () => observed!.certificateTrustPath.single.derBytes[0] = 0,
        throwsUnsupportedError,
      );

      reject = false;
      final saved = await fixture.feature.finishRegistration(
        context: fixture.context,
        user: fixture.user,
        credential: credential,
      );
      expect(saved.userId, fixture.user.id);
    });

    test(
      'policy exceptions are generic and leave the challenge retryable',
      () async {
        var throwsPolicyError = true;
        final fixture = _Fixture(
          attestationTrustPolicy: WebAuthnAttestationTrustPolicy(
            evaluateCertificate: (_) {
              if (throwsPolicyError) {
                throw StateError('certificate parser internals');
              }
              return WebAuthnAttestationTrustDecision.downgrade;
            },
          ),
        );
        final attestationKey = _KeyPair.create(privateValue: BigInt.two);
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final credential = _registrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
          attestationFormat: 'packed',
          packedSigningKey: attestationKey,
          packedCertificateChain: <Object?>[
            _packedAttestationCertificate(attestationKey),
          ],
        );

        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: credential,
          ),
          throwsA(
            isA<AuthFlowException>()
                .having(
                  (error) => error.code,
                  'code',
                  'webauthn_attestation_untrusted',
                )
                .having(
                  (error) => error.toString(),
                  'public representation',
                  isNot(contains('parser')),
                ),
          ),
        );

        throwsPolicyError = false;
        final saved = await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: credential,
        );
        expect(saved.userId, fixture.user.id);
      },
    );

    test('none and self attestation have explicit policy decisions', () async {
      Future<void> expectRejected({required bool selfAttestation}) async {
        final fixture = _Fixture(
          attestationTrustPolicy: WebAuthnAttestationTrustPolicy(
            none: selfAttestation
                ? WebAuthnUnprovenAttestationDecision.accept
                : WebAuthnUnprovenAttestationDecision.reject,
            self: selfAttestation
                ? WebAuthnUnprovenAttestationDecision.reject
                : WebAuthnUnprovenAttestationDecision.accept,
          ),
        );
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: _registrationCredential(
              challenge: registration.challenge,
              keyPair: fixture.keyPair,
              attestationFormat: selfAttestation ? 'packed' : 'none',
            ),
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'webauthn_attestation_untrusted',
            ),
          ),
        );
      }

      await expectRejected(selfAttestation: false);
      await expectRejected(selfAttestation: true);
    });

    test(
      'FIDO U2F trust evaluation receives its validated leaf only',
      () async {
        WebAuthnAttestationMetadata? observed;
        final fixture = _Fixture(
          attestationTrustPolicy: WebAuthnAttestationTrustPolicy(
            evaluateCertificate: (metadata) {
              observed = metadata;
              return WebAuthnAttestationTrustDecision.downgrade;
            },
          ),
        );
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );

        await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _u2fRegistrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
          ),
        );

        expect(observed?.format, 'fido-u2f');
        expect(observed?.kind, WebAuthnAttestationKind.certificate);
        expect(observed?.certificateTrustPath, hasLength(1));
      },
    );

    test('registers certificate-backed packed RS256 attestation', () async {
      final fixture = _Fixture();
      final keyPair = _RsaKeyPair.create();
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );

      final saved = await fixture.feature.finishRegistration(
        context: fixture.context,
        user: fixture.user,
        credential: _rsaRegistrationCredential(
          challenge: registration.challenge,
          keyPair: keyPair,
          certificateChain: <Object?>[
            _packedRsaAttestationCertificate(keyPair),
          ],
        ),
      );

      expect(saved.userId, fixture.user.id);
    });

    test('rejects malformed certificate-backed packed attestation', () async {
      var policyCalled = false;
      final fixture = _Fixture(
        attestationTrustPolicy: WebAuthnAttestationTrustPolicy(
          evaluateCertificate: (_) {
            policyCalled = true;
            return WebAuthnAttestationTrustDecision.accept;
          },
        ),
      );
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );

      await expectLater(
        () => fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _registrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
            attestationFormat: 'packed',
            packedCertificateChain: <Object?>[
              List<int>.generate(32, (index) => index),
            ],
          ),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'webauthn_attestation_invalid',
          ),
        ),
      );
      expect(policyCalled, isFalse);
    });

    test('rejects a forged certificate-backed packed signature', () async {
      final fixture = _Fixture();
      final attestationKey = _KeyPair.create(privateValue: BigInt.two);
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );

      await expectLater(
        () => fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _registrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
            attestationFormat: 'packed',
            packedSigningKey: attestationKey,
            corruptPackedSignature: true,
            packedCertificateChain: <Object?>[
              _packedAttestationCertificate(attestationKey),
            ],
          ),
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            'webauthn_attestation_invalid',
          ),
        ),
      );
    });

    test(
      'rejects packed attestation certificates with invalid subject',
      () async {
        final fixture = _Fixture();
        final attestationKey = _KeyPair.create(privateValue: BigInt.two);
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );

        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: _registrationCredential(
              challenge: registration.challenge,
              keyPair: fixture.keyPair,
              attestationFormat: 'packed',
              packedSigningKey: attestationKey,
              packedCertificateChain: <Object?>[
                _packedAttestationCertificate(
                  attestationKey,
                  organizationalUnit: 'Not an authenticator',
                ),
              ],
            ),
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'webauthn_attestation_invalid',
            ),
          ),
        );
      },
    );

    test(
      'rejects packed attestation certificates without basic constraints',
      () async {
        final fixture = _Fixture();
        final attestationKey = _KeyPair.create(privateValue: BigInt.two);
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );

        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: _registrationCredential(
              challenge: registration.challenge,
              keyPair: fixture.keyPair,
              attestationFormat: 'packed',
              packedSigningKey: attestationKey,
              packedCertificateChain: <Object?>[
                _packedAttestationCertificate(
                  attestationKey,
                  includeBasicConstraints: false,
                ),
              ],
            ),
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              'webauthn_attestation_invalid',
            ),
          ),
        );
      },
    );

    test('authenticates an RS256 passkey', () async {
      final fixture = _Fixture();
      final keyPair = _RsaKeyPair.create();
      final credentialId = base64UrlNoPadding(
        Uint8List.fromList(utf8.encode('rsa-credential')),
      );
      await fixture.store.users.create(fixture.user);
      await fixture.store.webAuthnAuthenticators.create(
        WebAuthnAuthenticator(
          credentialId: credentialId,
          publicKey: base64UrlNoPadding(keyPair.cosePublicKey),
          counter: 0,
          userId: fixture.user.id,
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final authentication = await fixture.feature.beginAuthentication(
        context: fixture.context,
        userId: fixture.user.id,
      );
      final result = await fixture.feature.finishAuthentication(
        context: fixture.context,
        credential: _rsaAssertionCredential(
          challenge: authentication.challenge,
          credentialId: credentialId,
          keyPair: keyPair,
          counter: 1,
        ),
        userId: fixture.user.id,
      );

      expect(result.user.id, fixture.user.id);
      expect(result.authenticator.counter, 1);
    });

    test(
      'issues a server session through the authentication endpoint',
      () async {
        final fixture = _Fixture();
        await fixture.store.users.create(fixture.user);
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final saved = await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _registrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
          ),
        );
        final authentication = await fixture.feature.beginAuthentication(
          context: fixture.context,
          userId: fixture.user.id,
        );
        final sessionControl = _RecordingSessionControl();
        final endpoint = fixture.feature.endpoints.firstWhere(
          (value) => value.id == 'webauthn.authenticationVerify',
        );

        final response = await endpoint.invoke(
          AuthOperationInvocation<Object>(
            context: fixture.context,
            user: null,
            sessionControl: sessionControl,
          ),
          <String, dynamic>{
            'credential': _assertionCredential(
              challenge: authentication.challenge,
              credentialId: saved.credentialId,
              keyPair: fixture.keyPair,
              counter: 1,
            ),
            'userId': fixture.user.id,
          },
        );

        final payload = response! as Map<String, dynamic>;
        expect(payload['status'], equals('authenticated'));
        expect(payload['session'], isA<Map<String, dynamic>>());
        expect(sessionControl.replacedUser?.id, equals(fixture.user.id));
        expect(sessionControl.authenticationMethod, equals('webauthn'));
      },
    );

    test('renames a registered passkey', () async {
      final fixture = _Fixture();
      await fixture.store.users.create(fixture.user);
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );
      final saved = await fixture.feature.finishRegistration(
        context: fixture.context,
        user: fixture.user,
        credential: _registrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
        ),
      );

      final renamed = await fixture.feature.renameCredential(
        userId: fixture.user.id,
        credentialId: saved.credentialId,
        name: '  Work laptop  ',
      );
      expect(renamed.name, 'Work laptop');
      expect(renamed.publicKey, saved.publicKey);
      expect(renamed.counter, saved.counter);
    });

    test(
      'rejects an origin mismatch without consuming the valid challenge',
      () async {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final invalid = _registrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
          origin: 'https://evil.example',
        );
        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: invalid,
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              equals('webauthn_origin_invalid'),
            ),
          ),
        );

        final saved = await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _registrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
          ),
        );
        expect(saved.credentialId, isNotEmpty);
      },
    );

    test('rejects assertion replay through the signature counter', () async {
      final fixture = _Fixture();
      await fixture.store.users.create(fixture.user);
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );
      final saved = await fixture.feature.finishRegistration(
        context: fixture.context,
        user: fixture.user,
        credential: _registrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
        ),
      );
      final authentication = await fixture.feature.beginAuthentication(
        context: fixture.context,
        userId: fixture.user.id,
      );
      final assertion = _assertionCredential(
        challenge: authentication.challenge,
        credentialId: saved.credentialId,
        keyPair: fixture.keyPair,
        counter: 1,
      );
      await fixture.feature.finishAuthentication(
        context: fixture.context,
        credential: assertion,
        userId: fixture.user.id,
      );

      await expectLater(
        () => fixture.feature.finishAuthentication(
          context: fixture.context,
          credential: assertion,
          userId: fixture.user.id,
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            equals('webauthn_challenge_invalid'),
          ),
        ),
      );

      final secondAuthentication = await fixture.feature.beginAuthentication(
        context: fixture.context,
        userId: fixture.user.id,
      );
      final replay = _assertionCredential(
        challenge: secondAuthentication.challenge,
        credentialId: saved.credentialId,
        keyPair: fixture.keyPair,
        counter: 1,
      );
      await expectLater(
        () => fixture.feature.finishAuthentication(
          context: fixture.context,
          credential: replay,
          userId: fixture.user.id,
        ),
        throwsA(
          isA<AuthFlowException>().having(
            (error) => error.code,
            'code',
            equals('webauthn_counter_replay'),
          ),
        ),
      );
    });

    test(
      'rejects non-byte attestation CBOR without leaking a cast error',
      () async {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final invalid = _registrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
        );
        final response = Map<String, dynamic>.from(invalid['response']! as Map)
          ..['attestationObject'] = base64UrlNoPadding(
            cbor.cbor.encode(<String, Object?>{
              'fmt': 'none',
              'authData': <Object?>[0, 'not-a-byte'],
              'attStmt': <String, Object?>{},
            }),
          );
        invalid['response'] = response;

        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: invalid,
          ),
          throwsA(
            isA<AuthFlowException>().having(
              (error) => error.code,
              'code',
              equals('webauthn_attestation_invalid'),
            ),
          ),
        );
      },
    );
  });

  test('malformed ceremony input stays inside stable auth errors', () async {
    final runner = PropertyTestRunner<String>(
      Chaos.string(minLength: 0, maxLength: 512),
      (value) async {
        final fixture = _Fixture();
        await expectLater(
          () => fixture.feature.finishAuthentication(
            context: fixture.context,
            credential: <String, dynamic>{
              'id': value,
              'rawId': value,
              'type': 'public-key',
              'response': <String, dynamic>{
                'clientDataJSON': value,
                'authenticatorData': value,
                'signature': value,
              },
            },
          ),
          throwsA(isA<AuthFlowException>()),
        );
      },
      PropertyConfig(numTests: 500, seed: 20260819),
    );
    final result = await runner.run();
    expect(result.success, isTrue, reason: _propertyReport(result));
  });

  test(
    'property: malformed assertion bytes remain stable auth errors',
    () async {
      final fixture = _Fixture();
      await fixture.store.users.create(fixture.user);
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );
      final saved = await fixture.feature.finishRegistration(
        context: fixture.context,
        user: fixture.user,
        credential: _registrationCredential(
          challenge: registration.challenge,
          keyPair: fixture.keyPair,
        ),
      );
      final runner = PropertyTestRunner<String>(
        Chaos.string(minLength: 0, maxLength: 512),
        (value) async {
          final authentication = await fixture.feature.beginAuthentication(
            context: fixture.context,
            userId: fixture.user.id,
          );
          final assertion = _assertionCredential(
            challenge: authentication.challenge,
            credentialId: saved.credentialId,
            keyPair: fixture.keyPair,
            counter: 1,
          );
          final response =
              Map<String, dynamic>.from(assertion['response']! as Map)
                ..['authenticatorData'] = value
                ..['signature'] = value;
          assertion['response'] = response;
          await expectLater(
            () => fixture.feature.finishAuthentication(
              context: fixture.context,
              credential: assertion,
              userId: fixture.user.id,
            ),
            throwsA(isA<AuthFlowException>()),
          );
        },
        PropertyConfig(numTests: 250, seed: 20260820),
      );
      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    },
  );
}

Future<Map<String, dynamic>> _ed25519RegistrationCredential({
  required String challenge,
  required _Ed25519KeyPair keyPair,
  String origin = 'https://example.com',
  String attestationFormat = 'none',
  List<int>? cosePublicKey,
}) async {
  final credentialId = Uint8List.fromList(
    List<int>.generate(16, (index) => 0x40 + index),
  );
  final coseKey =
      cosePublicKey ??
      cbor.cbor.encode(<Object?, Object?>{
        1: 1,
        3: -8,
        -1: 6,
        -2: keyPair.publicKey,
      });
  final authData = <int>[
    ...crypto.sha256.convert(utf8.encode('example.com')).bytes,
    0x41,
    0,
    0,
    0,
    0,
    ...List<int>.filled(16, 0),
    credentialId.length >> 8,
    credentialId.length & 0xff,
    ...credentialId,
    ...coseKey,
  ];
  final clientDataJson = _clientData(
    type: 'webauthn.create',
    challenge: challenge,
    origin: origin,
  );
  final attestationStatement = <String, Object?>{};
  if (attestationFormat == 'packed') {
    attestationStatement
      ..['alg'] = -8
      ..['sig'] = await keyPair.sign(<int>[
        ...authData,
        ...crypto.sha256.convert(clientDataJson).bytes,
      ]);
  }
  final attestationObject = cbor.cbor.encode(<String, Object?>{
    'fmt': attestationFormat,
    'authData': authData,
    'attStmt': attestationStatement,
  });
  final encodedId = base64UrlNoPadding(credentialId);
  return <String, dynamic>{
    'id': encodedId,
    'rawId': encodedId,
    'type': 'public-key',
    'response': <String, dynamic>{
      'clientDataJSON': base64UrlNoPadding(clientDataJson),
      'attestationObject': base64UrlNoPadding(attestationObject),
      'transports': <String>['internal'],
    },
  };
}

Future<Map<String, dynamic>> _ed25519AssertionCredential({
  required String challenge,
  required String credentialId,
  required _Ed25519KeyPair keyPair,
  required int counter,
  String origin = 'https://example.com',
}) async {
  final authenticatorData = <int>[
    ...crypto.sha256.convert(utf8.encode('example.com')).bytes,
    0x05,
    (counter >> 24) & 0xff,
    (counter >> 16) & 0xff,
    (counter >> 8) & 0xff,
    counter & 0xff,
  ];
  final clientDataJson = _clientData(
    type: 'webauthn.get',
    challenge: challenge,
    origin: origin,
  );
  final signature = await keyPair.sign(<int>[
    ...authenticatorData,
    ...crypto.sha256.convert(clientDataJson).bytes,
  ]);
  return <String, dynamic>{
    'id': credentialId,
    'rawId': credentialId,
    'type': 'public-key',
    'response': <String, dynamic>{
      'clientDataJSON': base64UrlNoPadding(clientDataJson),
      'authenticatorData': base64UrlNoPadding(authenticatorData),
      'signature': base64UrlNoPadding(signature),
    },
  };
}

Map<String, dynamic> _registrationCredential({
  required String challenge,
  required _KeyPair keyPair,
  String origin = 'https://example.com',
  String attestationFormat = 'none',
  int packedAlgorithm = -7,
  bool corruptPackedSignature = false,
  List<Object?>? packedCertificateChain,
  _KeyPair? packedSigningKey,
}) {
  final credentialId = Uint8List.fromList(
    List<int>.generate(16, (index) => index + 1),
  );
  final coseKey = cbor.cbor.encode(<Object?, Object?>{
    1: 2,
    3: -7,
    -1: 1,
    -2: keyPair.x.toList(growable: false),
    -3: keyPair.y.toList(growable: false),
  });
  final rpIdHash = crypto.sha256.convert(utf8.encode('example.com')).bytes;
  final authData = <int>[
    ...rpIdHash,
    0x41,
    0,
    0,
    0,
    0,
    ...List<int>.filled(16, 0),
    credentialId.length >> 8,
    credentialId.length & 0xff,
    ...credentialId,
    ...coseKey,
  ];
  final clientDataJson = _clientData(
    type: 'webauthn.create',
    challenge: challenge,
    origin: origin,
  );
  final attestationStatement = <String, Object?>{};
  if (attestationFormat == 'packed') {
    final signature = _signEs256(packedSigningKey ?? keyPair, <int>[
      ...authData,
      ...crypto.sha256.convert(clientDataJson).bytes,
    ]);
    if (corruptPackedSignature) {
      signature[signature.length - 1] ^= 0x01;
    }
    attestationStatement
      ..['alg'] = packedAlgorithm
      ..['sig'] = signature;
    if (packedCertificateChain != null) {
      attestationStatement['x5c'] = packedCertificateChain;
    }
  }
  final attestationObject = cbor.cbor.encode(<String, Object?>{
    'fmt': attestationFormat,
    'authData': authData,
    'attStmt': attestationStatement,
  });
  final encodedId = base64UrlNoPadding(credentialId);
  return <String, dynamic>{
    'id': encodedId,
    'rawId': encodedId,
    'type': 'public-key',
    'response': <String, dynamic>{
      'clientDataJSON': base64UrlNoPadding(clientDataJson),
      'attestationObject': base64UrlNoPadding(attestationObject),
      'transports': <String>['internal'],
    },
    'name': 'Laptop',
  };
}

Map<String, dynamic> _u2fRegistrationCredential({
  required String challenge,
  required _KeyPair keyPair,
  String origin = 'https://example.com',
  _KeyPair? attestationKey,
  List<Object?>? certificateChain,
  List<int>? cosePublicKey,
  bool corruptSignature = false,
  bool rawSignature = false,
  bool wrongVerificationData = false,
}) {
  final credentialId = Uint8List.fromList(
    List<int>.generate(16, (index) => index + 1),
  );
  final coseKey =
      cosePublicKey ??
      cbor.cbor.encode(<Object?, Object?>{
        1: 2,
        3: -7,
        -1: 1,
        -2: keyPair.x.toList(growable: false),
        -3: keyPair.y.toList(growable: false),
      });
  final rpIdHash = crypto.sha256.convert(utf8.encode('example.com')).bytes;
  final authData = <int>[
    ...rpIdHash,
    0x41,
    0,
    0,
    0,
    0,
    ...List<int>.filled(16, 0),
    credentialId.length >> 8,
    credentialId.length & 0xff,
    ...credentialId,
    ...coseKey,
  ];
  final clientDataJson = _clientData(
    type: 'webauthn.create',
    challenge: challenge,
    origin: origin,
  );
  final clientDataHash = crypto.sha256.convert(clientDataJson).bytes;
  final publicKeyU2F = <int>[0x04, ...keyPair.x, ...keyPair.y];
  final verificationData = <int>[
    0x00,
    ...rpIdHash,
    ...clientDataHash,
    ...credentialId,
    ...publicKeyU2F,
  ];
  final signingKey =
      attestationKey ?? _KeyPair.create(privateValue: BigInt.two);
  final derSignature = _signEs256(
    signingKey,
    wrongVerificationData ? verificationData.sublist(1) : verificationData,
  );
  final signature = rawSignature
      ? _rawEs256Signature(derSignature)
      : derSignature;
  if (corruptSignature) signature[signature.length - 1] ^= 0x01;
  final attestationObject = cbor.cbor.encode(<String, Object?>{
    'fmt': 'fido-u2f',
    'authData': authData,
    'attStmt': <String, Object?>{
      'x5c':
          certificateChain ??
          <Object?>[_packedAttestationCertificate(signingKey)],
      'sig': signature,
    },
  });
  final encodedId = base64UrlNoPadding(credentialId);
  return <String, dynamic>{
    'id': encodedId,
    'rawId': encodedId,
    'type': 'public-key',
    'response': <String, dynamic>{
      'clientDataJSON': base64UrlNoPadding(clientDataJson),
      'attestationObject': base64UrlNoPadding(attestationObject),
      'transports': <String>['usb'],
    },
  };
}

Map<String, dynamic> _assertionCredential({
  required String challenge,
  required String credentialId,
  required _KeyPair keyPair,
  required int counter,
  String origin = 'https://example.com',
}) {
  final authenticatorData = <int>[
    ...crypto.sha256.convert(utf8.encode('example.com')).bytes,
    0x05,
    (counter >> 24) & 0xff,
    (counter >> 16) & 0xff,
    (counter >> 8) & 0xff,
    counter & 0xff,
  ];
  final clientDataJson = _clientData(
    type: 'webauthn.get',
    challenge: challenge,
    origin: origin,
  );
  final clientDataHash = crypto.sha256.convert(clientDataJson).bytes;
  final signedData = <int>[...authenticatorData, ...clientDataHash];
  final signature = _signEs256(keyPair, signedData);
  return <String, dynamic>{
    'id': credentialId,
    'rawId': credentialId,
    'type': 'public-key',
    'response': <String, dynamic>{
      'clientDataJSON': base64UrlNoPadding(clientDataJson),
      'authenticatorData': base64UrlNoPadding(authenticatorData),
      'signature': base64UrlNoPadding(signature),
    },
  };
}

Map<String, dynamic> _rsaRegistrationCredential({
  required String challenge,
  required _RsaKeyPair keyPair,
  List<Object?>? certificateChain,
}) {
  final credentialId = Uint8List.fromList(
    List<int>.generate(16, (index) => 0x20 + index),
  );
  final rpIdHash = crypto.sha256.convert(utf8.encode('example.com')).bytes;
  final authData = <int>[
    ...rpIdHash,
    0x41,
    0,
    0,
    0,
    0,
    ...List<int>.filled(16, 0),
    credentialId.length >> 8,
    credentialId.length & 0xff,
    ...credentialId,
    ...keyPair.cosePublicKey,
  ];
  final clientDataJson = _clientData(
    type: 'webauthn.create',
    challenge: challenge,
    origin: 'https://example.com',
  );
  final signature = _signRs256(keyPair, <int>[
    ...authData,
    ...crypto.sha256.convert(clientDataJson).bytes,
  ]);
  final attestationObject = cbor.cbor.encode(<String, Object?>{
    'fmt': 'packed',
    'authData': authData,
    'attStmt': <String, Object?>{
      'alg': -257,
      'sig': signature,
      'x5c': ?certificateChain,
    },
  });
  final encodedId = base64UrlNoPadding(credentialId);
  return <String, dynamic>{
    'id': encodedId,
    'rawId': encodedId,
    'type': 'public-key',
    'response': <String, dynamic>{
      'clientDataJSON': base64UrlNoPadding(clientDataJson),
      'attestationObject': base64UrlNoPadding(attestationObject),
      'transports': <String>['usb'],
    },
  };
}

Uint8List _clientData({
  required String type,
  required String challenge,
  required String origin,
}) {
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, dynamic>{
        'type': type,
        'challenge': challenge,
        'origin': origin,
        'crossOrigin': false,
      }),
    ),
  );
}

Uint8List _signEs256(_KeyPair keyPair, List<int> message) {
  final random = FortunaRandom()
    ..seed(
      KeyParameter(Uint8List.fromList(List<int>.generate(32, (i) => i + 1))),
    );
  final signer = ECDSASigner(SHA256Digest())
    ..init(
      true,
      ParametersWithRandom(
        PrivateKeyParameter<ECPrivateKey>(keyPair.privateKey),
        random,
      ),
    );
  final signature = signer.generateSignature(Uint8List.fromList(message));
  if (signature is! ECSignature) throw StateError('Expected ECDSA signature');
  final r = _derInteger(signature.r);
  final s = _derInteger(signature.s);
  return Uint8List.fromList(<int>[0x30, r.length + s.length, ...r, ...s]);
}

Uint8List _rawEs256Signature(Uint8List derSignature) {
  final parser = ASN1Parser(derSignature);
  final sequence = parser.nextObject();
  if (parser.hasNext() ||
      sequence is! ASN1Sequence ||
      sequence.elements?.length != 2 ||
      sequence.elements![0] is! ASN1Integer ||
      sequence.elements![1] is! ASN1Integer) {
    throw StateError('Expected a DER ECDSA signature');
  }
  final r = (sequence.elements![0] as ASN1Integer).integer;
  final s = (sequence.elements![1] as ASN1Integer).integer;
  if (r == null || s == null) {
    throw StateError('Expected ECDSA signature integers');
  }
  return Uint8List.fromList(<int>[
    ..._bigIntBytes(r, 32),
    ..._bigIntBytes(s, 32),
  ]);
}

List<int> _derInteger(BigInt value) {
  var bytes = _bigIntBytes(value, 32);
  while (bytes.length > 1 && bytes.first == 0) {
    bytes = bytes.sublist(1);
  }
  if (bytes.first & 0x80 != 0) bytes = <int>[0, ...bytes];
  return <int>[0x02, bytes.length, ...bytes];
}

Map<String, dynamic> _rsaAssertionCredential({
  required String challenge,
  required String credentialId,
  required _RsaKeyPair keyPair,
  required int counter,
}) {
  final authenticatorData = <int>[
    ...crypto.sha256.convert(utf8.encode('example.com')).bytes,
    0x05,
    (counter >> 24) & 0xff,
    (counter >> 16) & 0xff,
    (counter >> 8) & 0xff,
    counter & 0xff,
  ];
  final clientDataJson = _clientData(
    type: 'webauthn.get',
    challenge: challenge,
    origin: 'https://example.com',
  );
  final signedData = <int>[
    ...authenticatorData,
    ...crypto.sha256.convert(clientDataJson).bytes,
  ];
  final signature = _signRs256(keyPair, signedData);
  return <String, dynamic>{
    'id': credentialId,
    'rawId': credentialId,
    'type': 'public-key',
    'response': <String, dynamic>{
      'clientDataJSON': base64UrlNoPadding(clientDataJson),
      'authenticatorData': base64UrlNoPadding(authenticatorData),
      'signature': base64UrlNoPadding(signature),
    },
  };
}

Uint8List _signRs256(_RsaKeyPair keyPair, List<int> message) {
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(keyPair.privateKey));
  final signature = signer.generateSignature(Uint8List.fromList(message));
  return Uint8List.fromList(signature.bytes);
}

List<int> _bigIntBytes(BigInt value, int length) {
  final result = List<int>.filled(length, 0);
  var current = value;
  for (var index = length - 1; index >= 0; index--) {
    result[index] = (current & BigInt.from(0xff)).toInt();
    current >>= 8;
  }
  return result;
}

Uint8List _packedAttestationCertificate(
  _KeyPair keyPair, {
  String organizationalUnit = 'Authenticator Attestation',
  bool includeBasicConstraints = true,
}) {
  final signatureAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.4.3.2'));
  final subject = _certificateName(organizationalUnit);
  final publicKeyAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.2.1'))
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.3.1.7'));
  final subjectPublicKeyInfo = ASN1Sequence()
    ..add(publicKeyAlgorithm)
    ..add(ASN1BitString(stringValues: <int>[0x04, ...keyPair.x, ...keyPair.y]));
  final basicConstraints = ASN1Sequence();
  final extensions = ASN1Sequence();
  if (includeBasicConstraints) {
    extensions.add(
      ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.19'))
        ..add(ASN1Boolean(true))
        ..add(ASN1OctetString(octets: basicConstraints.encode())),
    );
  }
  extensions.add(
    ASN1Sequence()
      ..add(
        ASN1ObjectIdentifier.fromIdentifierString('1.3.6.1.4.1.45724.1.1.4'),
      )
      ..add(
        ASN1OctetString(
          octets: ASN1OctetString(octets: Uint8List(16)).encode(),
        ),
      ),
  );
  final tbsCertificate = ASN1Sequence()
    ..add(_explicitAsn1(0xa0, ASN1Integer(BigInt.two).encode()))
    ..add(ASN1Integer(BigInt.one))
    ..add(signatureAlgorithm)
    ..add(subject)
    ..add(
      ASN1Sequence()
        ..add(ASN1UtcTime(DateTime.utc(2020, 1, 1)))
        ..add(ASN1UtcTime(DateTime.utc(2040, 1, 1))),
    )
    ..add(subject)
    ..add(subjectPublicKeyInfo)
    ..add(_explicitAsn1(0xa3, extensions.encode()));
  final tbsBytes = tbsCertificate.encode();
  final signature = _signEs256(keyPair, tbsBytes);
  return Uint8List.fromList(
    (ASN1Sequence()
          ..add(tbsCertificate)
          ..add(signatureAlgorithm)
          ..add(ASN1BitString(stringValues: signature)))
        .encode(),
  );
}

Uint8List _packedRsaAttestationCertificate(_RsaKeyPair keyPair) {
  final signatureAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.11'))
    ..add(ASN1Null());
  final publicKeyAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'))
    ..add(ASN1Null());
  final rsaPublicKey = ASN1Sequence()
    ..add(ASN1Integer(keyPair.publicKey.modulus!))
    ..add(ASN1Integer(keyPair.publicKey.publicExponent!));
  final subjectPublicKeyInfo = ASN1Sequence()
    ..add(publicKeyAlgorithm)
    ..add(ASN1BitString(stringValues: rsaPublicKey.encode()));
  final subject = _certificateName('Authenticator Attestation');
  final basicConstraints = ASN1Sequence();
  final extensions = ASN1Sequence()
    ..add(
      ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.19'))
        ..add(ASN1Boolean(true))
        ..add(ASN1OctetString(octets: basicConstraints.encode())),
    )
    ..add(
      ASN1Sequence()
        ..add(
          ASN1ObjectIdentifier.fromIdentifierString('1.3.6.1.4.1.45724.1.1.4'),
        )
        ..add(
          ASN1OctetString(
            octets: ASN1OctetString(octets: Uint8List(16)).encode(),
          ),
        ),
    );
  final tbsCertificate = ASN1Sequence()
    ..add(_explicitAsn1(0xa0, ASN1Integer(BigInt.two).encode()))
    ..add(ASN1Integer(BigInt.two))
    ..add(signatureAlgorithm)
    ..add(subject)
    ..add(
      ASN1Sequence()
        ..add(ASN1UtcTime(DateTime.utc(2020, 1, 1)))
        ..add(ASN1UtcTime(DateTime.utc(2040, 1, 1))),
    )
    ..add(subject)
    ..add(subjectPublicKeyInfo)
    ..add(_explicitAsn1(0xa3, extensions.encode()));
  final signature = _signRs256(keyPair, tbsCertificate.encode());
  return Uint8List.fromList(
    (ASN1Sequence()
          ..add(tbsCertificate)
          ..add(signatureAlgorithm)
          ..add(ASN1BitString(stringValues: signature)))
        .encode(),
  );
}

ASN1Sequence _certificateName(String organizationalUnit) => ASN1Sequence()
  ..add(_certificateNameAttribute('2.5.4.6', 'JM', printable: true))
  ..add(_certificateNameAttribute('2.5.4.10', 'Routed Tests'))
  ..add(_certificateNameAttribute('2.5.4.11', organizationalUnit))
  ..add(_certificateNameAttribute('2.5.4.3', 'Test Authenticator'));

ASN1Set _certificateNameAttribute(
  String identifier,
  String value, {
  bool printable = false,
}) => ASN1Set()
  ..add(
    ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromIdentifierString(identifier))
      ..add(
        printable
            ? ASN1PrintableString(stringValue: value)
            : ASN1UTF8String(utf8StringValue: value),
      ),
  );

ASN1Object _explicitAsn1(int tag, Uint8List value) {
  final object = ASN1Object(tag: tag)
    ..valueBytes = value
    ..valueByteLength = value.length;
  return object;
}

final class _KeyPair {
  _KeyPair._({required this.privateKey, required this.x, required this.y});

  factory _KeyPair.create({BigInt? privateValue}) {
    final parameters = ECDomainParameters('secp256r1');
    final value = privateValue ?? BigInt.one;
    final point = (parameters.G * value)!;
    return _KeyPair._(
      privateKey: ECPrivateKey(value, parameters),
      x: Uint8List.fromList(_bigIntBytes(point.x!.toBigInteger()!, 32)),
      y: Uint8List.fromList(_bigIntBytes(point.y!.toBigInteger()!, 32)),
    );
  }

  final ECPrivateKey privateKey;
  final Uint8List x;
  final Uint8List y;
}

final class _Ed25519KeyPair {
  _Ed25519KeyPair._({required this.keyPair, required this.publicKey});

  static Future<_Ed25519KeyPair> create() async {
    final algorithm = cryptography.Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(
      List<int>.generate(32, (index) => index + 1),
    );
    final publicKey = await keyPair.extractPublicKey();
    return _Ed25519KeyPair._(
      keyPair: keyPair,
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  final cryptography.SimpleKeyPair keyPair;
  final Uint8List publicKey;

  Future<Uint8List> sign(List<int> message) async {
    final signature = await cryptography.Ed25519().sign(
      message,
      keyPair: keyPair,
    );
    return Uint8List.fromList(signature.bytes);
  }
}

final class _RsaKeyPair {
  _RsaKeyPair._({
    required this.privateKey,
    required this.publicKey,
    required this.cosePublicKey,
  });

  factory _RsaKeyPair.create() {
    final random = FortunaRandom()
      ..seed(
        KeyParameter(Uint8List.fromList(List<int>.generate(32, (i) => i + 7))),
      );
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    final publicKey = pair.publicKey;
    final privateKey = pair.privateKey;
    final modulus = _bigIntBytes(
      publicKey.modulus!,
      (publicKey.modulus!.bitLength + 7) ~/ 8,
    );
    final exponent = _bigIntBytes(
      publicKey.publicExponent!,
      (publicKey.publicExponent!.bitLength + 7) ~/ 8,
    );
    return _RsaKeyPair._(
      privateKey: privateKey,
      publicKey: publicKey,
      cosePublicKey: Uint8List.fromList(
        cbor.cbor.encode(<Object?, Object?>{
          1: 3,
          3: -257,
          -1: modulus,
          -2: exponent,
        }),
      ),
    );
  }

  final RSAPrivateKey privateKey;
  final RSAPublicKey publicKey;
  final Uint8List cosePublicKey;
}
