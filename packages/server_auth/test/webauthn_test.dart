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
  @override
  AuthSessionStrategy get strategy => AuthSessionStrategy.session;

  @override
  String? get currentSessionId => null;

  @override
  Future<void> signOut() async {}
}

void main() {
  group('WebAuthn stores', () {
    test('challenge consumption is bound and one-time', () async {
      final store = InMemoryAuthWebAuthnChallengeStore();
      final created = DateTime.utc(2030);
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
      final created = DateTime.utc(2030);
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
        final created = DateTime.utc(2030);
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

        final authentication = await fixture.feature
            .beginUserBoundAuthentication(
              context: fixture.context,
              user: fixture.user,
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

    test('public options do not distinguish known and unknown users', () async {
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
      final endpoint = fixture.feature.endpoints.firstWhere(
        (value) => value.id == 'webauthn.authenticationOptions',
      );
      final invocation = AuthOperationInvocation<Object>(
        context: fixture.context,
        user: null,
      );

      final known = Map<String, dynamic>.from(
        (await endpoint.invoke(
              invocation,
              AuthEndpointRequest(
                body: <String, dynamic>{'userId': fixture.user.id},
              ),
            ))!
            as Map,
      );
      final unknown = Map<String, dynamic>.from(
        (await endpoint.invoke(
              invocation,
              AuthEndpointRequest(
                body: <String, dynamic>{'userId': 'unknown-user'},
              ),
            ))!
            as Map,
      );

      expect(known, isNot(contains('allowCredentials')));
      expect(unknown, isNot(contains('allowCredentials')));
      expect(jsonEncode(known), isNot(contains(saved.credentialId)));
      expect(jsonEncode(unknown), isNot(contains(saved.credentialId)));
      known.remove('challenge');
      unknown.remove('challenge');
      expect(known, equals(unknown));
    });

    test('only an authenticated principal receives credential IDs', () async {
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
      final endpoint = fixture.feature.endpoints.firstWhere(
        (value) => value.id == 'webauthn.authenticationOptions',
      );

      final own = Map<String, dynamic>.from(
        (await endpoint.invoke(
              AuthOperationInvocation<Object>(
                context: fixture.context,
                user: fixture.user,
              ),
              AuthEndpointRequest(),
            ))!
            as Map,
      );
      final other = Map<String, dynamic>.from(
        (await endpoint.invoke(
              AuthOperationInvocation<Object>(
                context: fixture.context,
                user: fixture.user,
              ),
              AuthEndpointRequest(
                body: const <String, dynamic>{'userId': 'another-user'},
              ),
            ))!
            as Map,
      );

      expect(
        own['allowCredentials'],
        equals(<Map<String, String>>[
          <String, String>{'type': 'public-key', 'id': saved.credentialId},
        ]),
      );
      expect(other, isNot(contains('allowCredentials')));
    });

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
      'registers browser-shaped TPM ES256 attestation through trust policy',
      () async {
        WebAuthnAttestationMetadata? observed;
        final fixture = _Fixture(
          attestationTrustPolicy: WebAuthnAttestationTrustPolicy(
            evaluateCertificate: (metadata) {
              observed = metadata;
              return WebAuthnAttestationTrustDecision.accept;
            },
          ),
        );
        await fixture.store.users.create(fixture.user);
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final saved = await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _tpmEs256RegistrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
          ),
        );

        expect(saved.name, 'TPM passkey');
        expect(observed?.format, 'tpm');
        expect(observed?.kind, WebAuthnAttestationKind.certificate);
        expect(observed?.certificateTrustPath, hasLength(2));
      },
    );

    test('registers browser-shaped TPM RS256 attestation', () async {
      final fixture = _Fixture(
        attestationTrustPolicy: const WebAuthnAttestationTrustPolicy(
          certificate: WebAuthnAttestationTrustDecision.accept,
        ),
      );
      final credentialKey = _RsaKeyPair.create();
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );
      final saved = await fixture.feature.finishRegistration(
        context: fixture.context,
        user: fixture.user,
        credential: _tpmRs256RegistrationCredential(
          challenge: registration.challenge,
          credentialKey: credentialKey,
        ),
      );

      expect(saved.name, 'TPM RSA passkey');
    });

    test('rejects malformed TPM statements and ECDAA', () async {
      final cases = <Map<String, dynamic> Function(String, _KeyPair)>[
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          version: '1.2',
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          statementAlgorithm: -8,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          includeEcdaa: true,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          unexpectedStatementField: true,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          duplicateStatementField: true,
        ),
      ];
      for (final credential in cases) {
        await _expectInvalidTpm(credential);
      }
    });

    test('rejects TPM certInfo and pubArea binding failures', () async {
      final cases = <Map<String, dynamic> Function(String, _KeyPair)>[
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          wrongCredentialKey: true,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          wrongExtraData: true,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          magic: 0xff544346,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          attestationType: 0x8018,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          wrongAttestedName: true,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          trailingPubArea: true,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          trailingCertInfo: true,
        ),
      ];
      for (final credential in cases) {
        await _expectInvalidTpm(credential);
      }
    });

    test('rejects forged TPM signatures and certificate chains', () async {
      final cases = <Map<String, dynamic> Function(String, _KeyPair)>[
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          corruptStatementSignature: true,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          forgedCertificateChain: true,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          certificateChain: <Object?>[List<int>.filled(16385, 0)],
        ),
      ];
      for (final credential in cases) {
        await _expectInvalidTpm(credential);
      }
    });

    test('rejects unsafe TPM attestation certificate semantics', () async {
      final cases = <Map<String, dynamic> Function(String, _KeyPair)>[
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          emptyLeafSubject: false,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          includeSubjectAlternativeName: false,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          criticalSubjectAlternativeName: false,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          duplicateSubjectAlternativeName: true,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          includeAikExtendedKeyUsage: false,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          includeBasicConstraints: false,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          leafIsCertificateAuthority: true,
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          certificateAaguid: List<int>.filled(16, 1),
        ),
      ];
      for (final credential in cases) {
        await _expectInvalidTpm(credential);
      }
    });

    test('rejects malformed and oversized TPM binary structures', () async {
      final cases = <Map<String, dynamic> Function(String, _KeyPair)>[
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          publicAreaOverride: <int>[0, 0x23, 0, 0x0b],
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          certInfoOverride: <int>[0xff, 0x54, 0x43, 0x47],
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          publicAreaOverride: List<int>.filled(16385, 0),
        ),
        (challenge, keyPair) => _tpmEs256RegistrationCredential(
          challenge: challenge,
          keyPair: keyPair,
          certInfoOverride: List<int>.filled(16385, 0),
        ),
      ];
      for (final credential in cases) {
        await _expectInvalidTpm(credential);
      }
    });

    test(
      'registers browser-shaped Android Key attestation through trust policy',
      () async {
        WebAuthnAttestationMetadata? observed;
        final fixture = _Fixture(
          attestationTrustPolicy: WebAuthnAttestationTrustPolicy(
            evaluateCertificate: (metadata) {
              observed = metadata;
              return WebAuthnAttestationTrustDecision.accept;
            },
          ),
        );
        await fixture.store.users.create(fixture.user);
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final saved = await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _androidKeyRegistrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
            purposeInSoftware: true,
          ),
        );

        expect(saved.name, 'Android passkey');
        expect(observed?.format, 'android-key');
        expect(observed?.kind, WebAuthnAttestationKind.certificate);
        expect(observed?.certificateTrustPath, hasLength(2));
        expect(observed?.certificateTrustPath.first.derBytes, isNotEmpty);

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
        expect(result.authenticator.counter, 1);
      },
    );

    test(
      'rejects forged Android Key statement and certificate signatures',
      () async {
        Future<void> expectInvalid(
          Map<String, dynamic> Function(String challenge, _KeyPair keyPair)
          credential,
        ) async {
          final fixture = _Fixture();
          final registration = await fixture.feature.beginRegistration(
            context: fixture.context,
            user: fixture.user,
          );
          await expectLater(
            () => fixture.feature.finishRegistration(
              context: fixture.context,
              user: fixture.user,
              credential: credential(registration.challenge, fixture.keyPair),
            ),
            throwsA(
              isA<AuthFlowException>()
                  .having(
                    (error) => error.code,
                    'code',
                    'webauthn_attestation_invalid',
                  )
                  .having(
                    (error) => error.toString(),
                    'public representation',
                    isNot(contains('certificate')),
                  ),
            ),
          );
        }

        await expectInvalid(
          (challenge, keyPair) => _androidKeyRegistrationCredential(
            challenge: challenge,
            keyPair: keyPair,
            corruptSignature: true,
          ),
        );
        await expectInvalid(
          (challenge, keyPair) => _androidKeyRegistrationCredential(
            challenge: challenge,
            keyPair: keyPair,
            certificateIssuerKey: _KeyPair.create(
              privateValue: BigInt.from(19),
            ),
          ),
        );
      },
    );

    test(
      'rejects Android Key leaf keys that differ from credentialPublicKey',
      () async {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final otherKey = _KeyPair.create(privateValue: BigInt.two);

        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: _androidKeyRegistrationCredential(
              challenge: registration.challenge,
              keyPair: fixture.keyPair,
              certificateKey: otherKey,
              statementSigningKey: otherKey,
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
      'rejects invalid Android Key authorization extension semantics',
      () async {
        final cases =
            <
              String,
              Map<String, dynamic> Function(String challenge, _KeyPair keyPair)
            >{
              'challenge': (challenge, keyPair) =>
                  _androidKeyRegistrationCredential(
                    challenge: challenge,
                    keyPair: keyPair,
                    extensionChallenge: List<int>.filled(32, 0),
                  ),
              'software allApplications': (challenge, keyPair) =>
                  _androidKeyRegistrationCredential(
                    challenge: challenge,
                    keyPair: keyPair,
                    softwareAllApplications: true,
                  ),
              'tee allApplications': (challenge, keyPair) =>
                  _androidKeyRegistrationCredential(
                    challenge: challenge,
                    keyPair: keyPair,
                    teeAllApplications: true,
                  ),
              'missing origin': (challenge, keyPair) =>
                  _androidKeyRegistrationCredential(
                    challenge: challenge,
                    keyPair: keyPair,
                    includeOrigin: false,
                  ),
              'imported origin': (challenge, keyPair) =>
                  _androidKeyRegistrationCredential(
                    challenge: challenge,
                    keyPair: keyPair,
                    origin: 2,
                  ),
              'missing purpose': (challenge, keyPair) =>
                  _androidKeyRegistrationCredential(
                    challenge: challenge,
                    keyPair: keyPair,
                    includePurpose: false,
                  ),
              'additional purpose': (challenge, keyPair) =>
                  _androidKeyRegistrationCredential(
                    challenge: challenge,
                    keyPair: keyPair,
                    purposes: const <int>{2, 3},
                  ),
            };

        for (final MapEntry(key: name, value: credential) in cases.entries) {
          final fixture = _Fixture();
          final registration = await fixture.feature.beginRegistration(
            context: fixture.context,
            user: fixture.user,
          );
          await expectLater(
            () => fixture.feature.finishRegistration(
              context: fixture.context,
              user: fixture.user,
              credential: credential(registration.challenge, fixture.keyPair),
            ),
            throwsA(
              isA<AuthFlowException>().having(
                (error) => error.code,
                'code for $name',
                'webauthn_attestation_invalid',
              ),
            ),
          );
        }
      },
    );

    test('rejects malformed and oversized Android Key extension DER', () async {
      final malformedExtensions = <List<int>>[
        <int>[0x30, 0x80, 0x00, 0x00],
        <int>[0x30, 0x03, 0x02, 0x02, 0x01],
        <int>[..._androidKeyDescription(challenge: List<int>.filled(32, 1)), 0],
        List<int>.filled(16385, 0),
      ];
      for (final extension in malformedExtensions) {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: _androidKeyRegistrationCredential(
              challenge: registration.challenge,
              keyPair: fixture.keyPair,
              extensionOverride: extension,
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
    });

    test('rejects missing extension, raw ES256, and unbounded x5c', () async {
      final cases =
          <Map<String, dynamic> Function(String challenge, _KeyPair keyPair)>[
            (challenge, keyPair) => _androidKeyRegistrationCredential(
              challenge: challenge,
              keyPair: keyPair,
              omitAndroidKeyExtension: true,
            ),
            (challenge, keyPair) => _androidKeyRegistrationCredential(
              challenge: challenge,
              keyPair: keyPair,
              rawStatementSignature: true,
            ),
            (challenge, keyPair) => _androidKeyRegistrationCredential(
              challenge: challenge,
              keyPair: keyPair,
              certificateChain: <Object?>[List<int>.filled(16385, 0)],
            ),
          ];
      for (final credential in cases) {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: credential(registration.challenge, fixture.keyPair),
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
    });

    test(
      'registers browser-shaped Apple attestation through trust policy',
      () async {
        WebAuthnAttestationMetadata? observed;
        final fixture = _Fixture(
          attestationTrustPolicy: WebAuthnAttestationTrustPolicy(
            evaluateCertificate: (metadata) {
              observed = metadata;
              return WebAuthnAttestationTrustDecision.accept;
            },
          ),
        );
        await fixture.store.users.create(fixture.user);
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        final saved = await fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _appleRegistrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
          ),
        );

        expect(saved.name, 'Apple passkey');
        expect(observed?.format, 'apple');
        expect(observed?.kind, WebAuthnAttestationKind.certificate);
        expect(observed?.certificateTrustPath, hasLength(2));
        expect(observed?.certificateTrustPath.first.derBytes, isNotEmpty);

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
        expect(result.authenticator.counter, 1);
      },
    );

    test('rejects Apple nonce and leaf-key mismatches', () async {
      final cases =
          <Map<String, dynamic> Function(String challenge, _KeyPair keyPair)>[
            (challenge, keyPair) => _appleRegistrationCredential(
              challenge: challenge,
              keyPair: keyPair,
              nonceOverride: List<int>.filled(32, 0),
            ),
            (challenge, keyPair) => _appleRegistrationCredential(
              challenge: challenge,
              keyPair: keyPair,
              certificateKey: _KeyPair.create(privateValue: BigInt.two),
            ),
          ];
      for (final credential in cases) {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: credential(registration.challenge, fixture.keyPair),
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
    });

    test('rejects forged or invalid Apple certificate chains', () async {
      final cases =
          <Map<String, dynamic> Function(String challenge, _KeyPair keyPair)>[
            (challenge, keyPair) => _appleRegistrationCredential(
              challenge: challenge,
              keyPair: keyPair,
              certificateIssuerKey: _KeyPair.create(
                privateValue: BigInt.from(23),
              ),
            ),
            (challenge, keyPair) => _appleRegistrationCredential(
              challenge: challenge,
              keyPair: keyPair,
              rootIsCertificateAuthority: false,
            ),
            (challenge, keyPair) => _appleRegistrationCredential(
              challenge: challenge,
              keyPair: keyPair,
              certificateChain: <Object?>[List<int>.filled(16385, 0)],
            ),
            (challenge, keyPair) => _appleRegistrationCredential(
              challenge: challenge,
              keyPair: keyPair,
              certificateChain: const <Object?>[],
            ),
          ];
      for (final credential in cases) {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: credential(registration.challenge, fixture.keyPair),
          ),
          throwsA(
            isA<AuthFlowException>()
                .having(
                  (error) => error.code,
                  'code',
                  'webauthn_attestation_invalid',
                )
                .having(
                  (error) => error.toString(),
                  'public representation',
                  isNot(anyOf(contains('certificate'), contains('nonce'))),
                ),
          ),
        );
      }
    });

    test('rejects malformed and duplicate Apple nonce extensions', () async {
      final malformed = <List<int>?>[
        null,
        <int>[0x30, 0x80, 0x00, 0x00],
        (ASN1Sequence()..add(ASN1OctetString(octets: Uint8List(31)))).encode(),
        (ASN1Sequence()
              ..add(ASN1OctetString(octets: Uint8List(32)))
              ..add(ASN1OctetString(octets: Uint8List(32))))
            .encode(),
        List<int>.filled(1025, 0),
      ];
      for (final extension in malformed) {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: _appleRegistrationCredential(
              challenge: registration.challenge,
              keyPair: fixture.keyPair,
              omitNonceExtension: extension == null,
              nonceExtensionOverride: extension,
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

      final fixture = _Fixture();
      final registration = await fixture.feature.beginRegistration(
        context: fixture.context,
        user: fixture.user,
      );
      await expectLater(
        () => fixture.feature.finishRegistration(
          context: fixture.context,
          user: fixture.user,
          credential: _appleRegistrationCredential(
            challenge: registration.challenge,
            keyPair: fixture.keyPair,
            duplicateNonceExtension: true,
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

    test('rejects unexpected and duplicate Apple statement fields', () async {
      for (final options in <({bool unexpected, bool duplicate})>[
        (unexpected: true, duplicate: false),
        (unexpected: false, duplicate: true),
      ]) {
        final fixture = _Fixture();
        final registration = await fixture.feature.beginRegistration(
          context: fixture.context,
          user: fixture.user,
        );
        await expectLater(
          () => fixture.feature.finishRegistration(
            context: fixture.context,
            user: fixture.user,
            credential: _appleRegistrationCredential(
              challenge: registration.challenge,
              keyPair: fixture.keyPair,
              unexpectedStatementField: options.unexpected,
              duplicateX5cField: options.duplicate,
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
    });

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

    test('accepts a leaf signed by an omitted trusted root', () async {
      final rootKey = _KeyPair.create(privateValue: BigInt.from(3));
      final attestationKey = _KeyPair.create(privateValue: BigInt.two);
      final rootCertificate = _androidTestCertificate(
        subjectKey: rootKey,
        issuerKey: rootKey,
        subjectOrganizationalUnit: 'Packed Root',
        issuerOrganizationalUnit: 'Packed Root',
        isCertificateAuthority: true,
      );
      final leafCertificate = _androidTestCertificate(
        subjectKey: attestationKey,
        issuerKey: rootKey,
        subjectOrganizationalUnit: 'Authenticator Attestation',
        issuerOrganizationalUnit: 'Packed Root',
      );
      final fixture = _Fixture(
        attestationTrustPolicy: WebAuthnAttestationTrustPolicy.trustedRoots(
          roots: <List<int>>[rootCertificate],
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
          packedCertificateChain: <Object?>[leafCertificate],
        ),
      );

      expect(saved.userId, fixture.user.id);
    });

    test(
      'accepts leaf and intermediate signed by an omitted trusted root',
      () async {
        final rootKey = _KeyPair.create(privateValue: BigInt.from(3));
        final intermediateKey = _KeyPair.create(privateValue: BigInt.from(4));
        final attestationKey = _KeyPair.create(privateValue: BigInt.two);
        final rootCertificate = _androidTestCertificate(
          subjectKey: rootKey,
          issuerKey: rootKey,
          subjectOrganizationalUnit: 'Packed Root',
          issuerOrganizationalUnit: 'Packed Root',
          isCertificateAuthority: true,
        );
        final intermediateCertificate = _androidTestCertificate(
          subjectKey: intermediateKey,
          issuerKey: rootKey,
          subjectOrganizationalUnit: 'Packed Intermediate',
          issuerOrganizationalUnit: 'Packed Root',
          isCertificateAuthority: true,
        );
        final leafCertificate = _androidTestCertificate(
          subjectKey: attestationKey,
          issuerKey: intermediateKey,
          subjectOrganizationalUnit: 'Authenticator Attestation',
          issuerOrganizationalUnit: 'Packed Intermediate',
        );
        final fixture = _Fixture(
          attestationTrustPolicy: WebAuthnAttestationTrustPolicy.trustedRoots(
            roots: <List<int>>[rootCertificate],
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
            packedCertificateChain: <Object?>[
              leafCertificate,
              intermediateCertificate,
            ],
          ),
        );

        expect(saved.userId, fixture.user.id);
      },
    );

    test('rejects a malformed configured trust anchor generically', () async {
      final attestationKey = _KeyPair.create(privateValue: BigInt.two);
      final fixture = _Fixture(
        attestationTrustPolicy: WebAuthnAttestationTrustPolicy.trustedRoots(
          roots: const <List<int>>[
            <int>[0x30, 0x00],
          ],
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
            packedSigningKey: attestationKey,
            packedCertificateChain: <Object?>[
              _packedAttestationCertificate(attestationKey),
            ],
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
    });

    test('rejects an omitted root with a forged signing key', () async {
      final trustedRootKey = _KeyPair.create(privateValue: BigInt.from(3));
      final forgedRootKey = _KeyPair.create(privateValue: BigInt.from(4));
      final attestationKey = _KeyPair.create(privateValue: BigInt.two);
      final trustedRoot = _androidTestCertificate(
        subjectKey: trustedRootKey,
        issuerKey: trustedRootKey,
        subjectOrganizationalUnit: 'Packed Root',
        issuerOrganizationalUnit: 'Packed Root',
        isCertificateAuthority: true,
      );
      final forgedLeaf = _androidTestCertificate(
        subjectKey: attestationKey,
        issuerKey: forgedRootKey,
        subjectOrganizationalUnit: 'Authenticator Attestation',
        issuerOrganizationalUnit: 'Packed Root',
      );
      final fixture = _Fixture(
        attestationTrustPolicy: WebAuthnAttestationTrustPolicy.trustedRoots(
          roots: <List<int>>[trustedRoot],
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
            packedSigningKey: attestationKey,
            packedCertificateChain: <Object?>[forgedLeaf],
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
    });

    test('rejects a non-CA intermediate in the trust path', () async {
      final rootKey = _KeyPair.create(privateValue: BigInt.from(3));
      final intermediateKey = _KeyPair.create(privateValue: BigInt.from(4));
      final attestationKey = _KeyPair.create(privateValue: BigInt.two);
      final rootCertificate = _androidTestCertificate(
        subjectKey: rootKey,
        issuerKey: rootKey,
        subjectOrganizationalUnit: 'Packed Root',
        issuerOrganizationalUnit: 'Packed Root',
        isCertificateAuthority: true,
      );
      final intermediateCertificate = _androidTestCertificate(
        subjectKey: intermediateKey,
        issuerKey: rootKey,
        subjectOrganizationalUnit: 'Packed Intermediate',
        issuerOrganizationalUnit: 'Packed Root',
      );
      final leafCertificate = _androidTestCertificate(
        subjectKey: attestationKey,
        issuerKey: intermediateKey,
        subjectOrganizationalUnit: 'Authenticator Attestation',
        issuerOrganizationalUnit: 'Packed Intermediate',
      );
      final fixture = _Fixture(
        attestationTrustPolicy: WebAuthnAttestationTrustPolicy.trustedRoots(
          roots: <List<int>>[rootCertificate],
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
            packedSigningKey: attestationKey,
            packedCertificateChain: <Object?>[
              leafCertificate,
              intermediateCertificate,
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

    test(
      'evaluates packed attestation provenance with an offline MDS blob',
      () async {
        final aaguid = List<int>.generate(16, (index) => index + 1);
        final attestationKey = _KeyPair.create(privateValue: BigInt.two);
        final certificate = _packedAttestationCertificate(
          attestationKey,
          aaguid: aaguid,
        );
        final metadata = await _loadFidoMetadata(
          certificate: certificate,
          aaguid: aaguid,
          status: 'FIDO_CERTIFIED',
        );
        final evaluator = FidoMetadataWebAuthnTrustEvaluator(blob: metadata);
        final fixture = _Fixture(
          attestationTrustPolicy: evaluator.asWebAuthnTrustPolicy(),
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
            aaguid: aaguid,
          ),
        );

        expect(saved.credentialId, isNotEmpty);
      },
    );

    test('rejects a revoked authenticator through the MDS policy', () async {
      final aaguid = List<int>.generate(16, (index) => index + 1);
      final attestationKey = _KeyPair.create(privateValue: BigInt.two);
      final certificate = _packedAttestationCertificate(
        attestationKey,
        aaguid: aaguid,
      );
      final metadata = await _loadFidoMetadata(
        certificate: certificate,
        aaguid: aaguid,
        status: 'REVOKED',
      );
      final fixture = _Fixture(
        attestationTrustPolicy: FidoMetadataWebAuthnTrustEvaluator(
          blob: metadata,
        ).asWebAuthnTrustPolicy(),
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
            packedSigningKey: attestationKey,
            packedCertificateChain: <Object?>[certificate],
            aaguid: aaguid,
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
    });

    test('rejects all security-critical MDS authenticator statuses', () async {
      final aaguid = List<int>.generate(16, (index) => index + 1);
      final attestationKey = _KeyPair.create(privateValue: BigInt.two);
      final certificate = _packedAttestationCertificate(
        attestationKey,
        aaguid: aaguid,
      );
      for (final status in <String>[
        'USER_VERIFICATION_BYPASS',
        'ATTESTATION_KEY_COMPROMISE',
        'USER_KEY_REMOTE_COMPROMISE',
        'USER_KEY_PHYSICAL_COMPROMISE',
        'FUTURE_UNKNOWN_STATUS',
      ]) {
        final metadata = await _loadFidoMetadata(
          certificate: certificate,
          aaguid: aaguid,
          status: status,
        );
        final fixture = _Fixture(
          attestationTrustPolicy: FidoMetadataWebAuthnTrustEvaluator(
            blob: metadata,
          ).asWebAuthnTrustPolicy(),
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
              packedSigningKey: attestationKey,
              packedCertificateChain: <Object?>[certificate],
              aaguid: aaguid,
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
    });

    test('uses the final MDS status report as the current status', () async {
      final aaguid = List<int>.generate(16, (index) => index + 1);
      final attestationKey = _KeyPair.create(privateValue: BigInt.two);
      final certificate = _packedAttestationCertificate(
        attestationKey,
        aaguid: aaguid,
      );
      final metadata = await _loadFidoMetadata(
        certificate: certificate,
        aaguid: aaguid,
        previousStatuses: const <String>['USER_VERIFICATION_BYPASS'],
        status: 'UPDATE_AVAILABLE',
      );
      final fixture = _Fixture(
        attestationTrustPolicy: FidoMetadataWebAuthnTrustEvaluator(
          blob: metadata,
          updateAvailable: WebAuthnAttestationTrustDecision.accept,
        ).asWebAuthnTrustPolicy(),
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
          aaguid: aaguid,
        ),
      );

      expect(saved.credentialId, isNotEmpty);
    });

    test(
      'allows an explicit downgrade policy for uncertified metadata',
      () async {
        final aaguid = List<int>.generate(16, (index) => index + 1);
        final attestationKey = _KeyPair.create(privateValue: BigInt.two);
        final certificate = _packedAttestationCertificate(
          attestationKey,
          aaguid: aaguid,
        );
        final metadata = await _loadFidoMetadata(
          certificate: certificate,
          aaguid: aaguid,
          status: 'NOT_FIDO_CERTIFIED',
        );
        final fixture = _Fixture(
          attestationTrustPolicy: FidoMetadataWebAuthnTrustEvaluator(
            blob: metadata,
            uncertified: WebAuthnAttestationTrustDecision.downgrade,
          ).asWebAuthnTrustPolicy(),
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
            aaguid: aaguid,
          ),
        );

        expect(saved.credentialId, isNotEmpty);
      },
    );

    test('rejects a certificate path outside MDS metadata roots', () async {
      final aaguid = List<int>.generate(16, (index) => index + 1);
      final attestationKey = _KeyPair.create(privateValue: BigInt.two);
      final certificate = _packedAttestationCertificate(
        attestationKey,
        aaguid: aaguid,
      );
      final unrelatedRoot = _packedAttestationCertificate(
        _KeyPair.create(privateValue: BigInt.from(3)),
        aaguid: aaguid,
      );
      final metadata = await _loadFidoMetadata(
        certificate: certificate,
        metadataRoot: unrelatedRoot,
        aaguid: aaguid,
        status: 'FIDO_CERTIFIED',
      );
      final fixture = _Fixture(
        attestationTrustPolicy: FidoMetadataWebAuthnTrustEvaluator(
          blob: metadata,
        ).asWebAuthnTrustPolicy(),
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
            packedSigningKey: attestationKey,
            packedCertificateChain: <Object?>[certificate],
            aaguid: aaguid,
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
          AuthEndpointRequest(
            body: <String, dynamic>{
              'credential': _assertionCredential(
                challenge: authentication.challenge,
                credentialId: saved.credentialId,
                keyPair: fixture.keyPair,
                counter: 1,
              ),
              'userId': fixture.user.id,
            },
          ),
        );

        final intent = response! as AuthEndpointAuthenticationIntent;
        expect(intent.user.id, equals(fixture.user.id));
        expect(intent.authenticationMethod, equals('webauthn'));
        final payload = await intent.projectResponse(
          AuthSession(
            user: intent.user,
            expiresAt: DateTime.utc(2030),
            strategy: AuthSessionStrategy.session,
          ).toJson(),
        );
        final payloadMap = payload! as Map<String, dynamic>;
        expect(payloadMap['status'], 'authenticated');
        expect(payloadMap['credential'], isA<Map<String, dynamic>>());
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

Future<void> _expectInvalidTpm(
  Map<String, dynamic> Function(String challenge, _KeyPair keyPair) credential,
) async {
  final fixture = _Fixture();
  final registration = await fixture.feature.beginRegistration(
    context: fixture.context,
    user: fixture.user,
  );
  await expectLater(
    () => fixture.feature.finishRegistration(
      context: fixture.context,
      user: fixture.user,
      credential: credential(registration.challenge, fixture.keyPair),
    ),
    throwsA(
      isA<AuthFlowException>()
          .having(
            (error) => error.code,
            'code',
            anyOf(
              'webauthn_attestation_invalid',
              'webauthn_attestation_unsupported',
            ),
          )
          .having(
            (error) => error.toString(),
            'public representation',
            isNot(
              anyOf(
                contains('certInfo'),
                contains('pubArea'),
                contains('certificate'),
              ),
            ),
          ),
    ),
  );
}

Map<String, dynamic> _tpmEs256RegistrationCredential({
  required String challenge,
  required _KeyPair keyPair,
  String version = '2.0',
  int statementAlgorithm = -7,
  bool includeEcdaa = false,
  bool unexpectedStatementField = false,
  bool duplicateStatementField = false,
  bool wrongCredentialKey = false,
  bool wrongExtraData = false,
  int magic = 0xff544347,
  int attestationType = 0x8017,
  bool wrongAttestedName = false,
  bool trailingPubArea = false,
  bool trailingCertInfo = false,
  bool corruptStatementSignature = false,
  bool forgedCertificateChain = false,
  bool emptyLeafSubject = true,
  bool includeSubjectAlternativeName = true,
  bool criticalSubjectAlternativeName = true,
  bool duplicateSubjectAlternativeName = false,
  bool includeAikExtendedKeyUsage = true,
  bool includeBasicConstraints = true,
  bool leafIsCertificateAuthority = false,
  List<int>? certificateAaguid,
  List<int>? publicAreaOverride,
  List<int>? certInfoOverride,
  List<Object?>? certificateChain,
}) {
  final credentialId = Uint8List.fromList(
    List<int>.generate(16, (index) => index + 1),
  );
  final coseKey = cbor.cbor.encode(<Object?, Object?>{
    1: 2,
    3: -7,
    -1: 1,
    -2: keyPair.x,
    -3: keyPair.y,
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
    origin: 'https://example.com',
  );
  final clientDataHash = crypto.sha256.convert(clientDataJson).bytes;
  final publicAreaKey = wrongCredentialKey
      ? _KeyPair.create(privateValue: BigInt.from(0x45))
      : keyPair;
  var pubArea = Uint8List.fromList(
    publicAreaOverride ?? _tpmEcPublicArea(publicAreaKey),
  );
  if (trailingPubArea) {
    pubArea = Uint8List.fromList(<int>[...pubArea, 0]);
  }
  final extraData = wrongExtraData
      ? List<int>.filled(32, 0)
      : crypto.sha256.convert(<int>[...authData, ...clientDataHash]).bytes;
  var certInfo = Uint8List.fromList(
    certInfoOverride ??
        _tpmCertInfo(
          publicArea: pubArea,
          extraData: extraData,
          magic: magic,
          type: attestationType,
          wrongName: wrongAttestedName,
        ),
  );
  if (trailingCertInfo) {
    certInfo = Uint8List.fromList(<int>[...certInfo, 0]);
  }

  final rootKey = _KeyPair.create(privateValue: BigInt.from(0x41));
  final aikKey = _KeyPair.create(privateValue: BigInt.from(0x42));
  final rootName = _certificateName('TPM Attestation Root');
  final rootCertificate = _tpmEcCertificate(
    subjectKey: rootKey,
    issuerKey: rootKey,
    subject: rootName,
    issuer: rootName,
    isCertificateAuthority: true,
  );
  final leafCertificate = _tpmEcCertificate(
    subjectKey: aikKey,
    issuerKey: forgedCertificateChain
        ? _KeyPair.create(privateValue: BigInt.from(0x43))
        : rootKey,
    subject: emptyLeafSubject
        ? ASN1Sequence()
        : _certificateName('TPM Attestation Key'),
    issuer: rootName,
    includeTpmSubjectAlternativeName: includeSubjectAlternativeName,
    criticalTpmSubjectAlternativeName: criticalSubjectAlternativeName,
    duplicateTpmSubjectAlternativeName: duplicateSubjectAlternativeName,
    includeTpmAikExtendedKeyUsage: includeAikExtendedKeyUsage,
    includeBasicConstraints: includeBasicConstraints,
    isCertificateAuthority: leafIsCertificateAuthority,
    aaguid: certificateAaguid,
  );
  final signature = _signEs256(aikKey, certInfo);
  if (corruptStatementSignature) signature[signature.length - 1] ^= 1;
  final chain = certificateChain ?? <Object?>[leafCertificate, rootCertificate];
  final statement = <String, Object?>{
    'ver': version,
    'alg': statementAlgorithm,
    'x5c': chain,
    'sig': signature,
    'certInfo': certInfo,
    'pubArea': pubArea,
    if (includeEcdaa) 'ecdaaKeyId': <int>[1],
    if (unexpectedStatementField) 'unexpected': true,
  };
  final attestationObject = duplicateStatementField
      ? Uint8List.fromList(<int>[
          0xa3,
          ...cbor.cbor.encode('fmt'),
          ...cbor.cbor.encode('tpm'),
          ...cbor.cbor.encode('authData'),
          ...cbor.cbor.encode(authData),
          ...cbor.cbor.encode('attStmt'),
          0xa7,
          ...cbor.cbor.encode('ver'),
          ...cbor.cbor.encode(version),
          ...cbor.cbor.encode('alg'),
          ...cbor.cbor.encode(statementAlgorithm),
          ...cbor.cbor.encode('alg'),
          ...cbor.cbor.encode(statementAlgorithm),
          ...cbor.cbor.encode('x5c'),
          ...cbor.cbor.encode(chain),
          ...cbor.cbor.encode('sig'),
          ...cbor.cbor.encode(signature),
          ...cbor.cbor.encode('certInfo'),
          ...cbor.cbor.encode(certInfo),
          ...cbor.cbor.encode('pubArea'),
          ...cbor.cbor.encode(pubArea),
        ])
      : Uint8List.fromList(
          cbor.cbor.encode(<String, Object?>{
            'fmt': 'tpm',
            'authData': authData,
            'attStmt': statement,
          }),
        );
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
    'name': 'TPM passkey',
  };
}

Map<String, dynamic> _tpmRs256RegistrationCredential({
  required String challenge,
  required _RsaKeyPair credentialKey,
}) {
  final credentialId = Uint8List.fromList(
    List<int>.generate(16, (index) => 0x20 + index),
  );
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
    ...credentialKey.cosePublicKey,
  ];
  final clientDataJson = _clientData(
    type: 'webauthn.create',
    challenge: challenge,
    origin: 'https://example.com',
  );
  final clientDataHash = crypto.sha256.convert(clientDataJson).bytes;
  final pubArea = _tpmRsaPublicArea(credentialKey);
  final certInfo = _tpmCertInfo(
    publicArea: pubArea,
    extraData: crypto.sha256.convert(<int>[
      ...authData,
      ...clientDataHash,
    ]).bytes,
  );
  final rootKey = _RsaKeyPair.create();
  final aikKey = _RsaKeyPair.create();
  final rootName = _certificateName('TPM RSA Attestation Root');
  final rootCertificate = _tpmRsaCertificate(
    subjectKey: rootKey,
    issuerKey: rootKey,
    subject: rootName,
    issuer: rootName,
    isCertificateAuthority: true,
  );
  final leafCertificate = _tpmRsaCertificate(
    subjectKey: aikKey,
    issuerKey: rootKey,
    subject: ASN1Sequence(),
    issuer: rootName,
    includeTpmSubjectAlternativeName: true,
    includeTpmAikExtendedKeyUsage: true,
  );
  final statement = <String, Object?>{
    'ver': '2.0',
    'alg': -257,
    'x5c': <Object?>[leafCertificate, rootCertificate],
    'sig': _signRs256(aikKey, certInfo),
    'certInfo': certInfo,
    'pubArea': pubArea,
  };
  final attestationObject = cbor.cbor.encode(<String, Object?>{
    'fmt': 'tpm',
    'authData': authData,
    'attStmt': statement,
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
    'name': 'TPM RSA passkey',
  };
}

Uint8List _tpmEcPublicArea(_KeyPair keyPair) => Uint8List.fromList(<int>[
  ..._tpmUint16(0x0023),
  ..._tpmUint16(0x000b),
  ..._tpmUint32(0x00040072),
  ..._tpmSized(const <int>[]),
  ..._tpmUint16(0x0010),
  ..._tpmUint16(0x0018),
  ..._tpmUint16(0x000b),
  ..._tpmUint16(0x0003),
  ..._tpmUint16(0x0010),
  ..._tpmSized(keyPair.x),
  ..._tpmSized(keyPair.y),
]);

Uint8List _tpmRsaPublicArea(_RsaKeyPair keyPair) {
  final modulus = _bigIntBytes(
    keyPair.publicKey.modulus!,
    (keyPair.publicKey.modulus!.bitLength + 7) ~/ 8,
  );
  return Uint8List.fromList(<int>[
    ..._tpmUint16(0x0001),
    ..._tpmUint16(0x000b),
    ..._tpmUint32(0x00040072),
    ..._tpmSized(const <int>[]),
    ..._tpmUint16(0x0010),
    ..._tpmUint16(0x0014),
    ..._tpmUint16(0x000b),
    ..._tpmUint16(2048),
    ..._tpmUint32(0),
    ..._tpmSized(modulus),
  ]);
}

Uint8List _tpmCertInfo({
  required List<int> publicArea,
  required List<int> extraData,
  int magic = 0xff544347,
  int type = 0x8017,
  bool wrongName = false,
}) {
  final nameDigest = crypto.sha256.convert(publicArea).bytes;
  final name = <int>[
    ..._tpmUint16(0x000b),
    ...(wrongName ? List<int>.filled(32, 0) : nameDigest),
  ];
  return Uint8List.fromList(<int>[
    ..._tpmUint32(magic),
    ..._tpmUint16(type),
    ..._tpmSized(const <int>[]),
    ..._tpmSized(extraData),
    ...List<int>.filled(8, 0),
    ..._tpmUint32(0),
    ..._tpmUint32(0),
    1,
    ...List<int>.filled(8, 0),
    ..._tpmSized(name),
    ..._tpmSized(const <int>[]),
  ]);
}

List<int> _tpmUint16(int value) => <int>[(value >> 8) & 0xff, value & 0xff];

List<int> _tpmUint32(int value) => <int>[
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

List<int> _tpmSized(List<int> value) => <int>[
  ..._tpmUint16(value.length),
  ...value,
];

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
  List<int>? aaguid,
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
    ...(aaguid ?? List<int>.filled(16, 0)),
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

Map<String, dynamic> _androidKeyRegistrationCredential({
  required String challenge,
  required _KeyPair keyPair,
  _KeyPair? rootKey,
  _KeyPair? certificateKey,
  _KeyPair? certificateIssuerKey,
  _KeyPair? statementSigningKey,
  List<int>? extensionChallenge,
  List<int>? extensionOverride,
  bool includePurpose = true,
  Set<int> purposes = const <int>{2},
  bool purposeInSoftware = false,
  bool includeOrigin = true,
  int origin = 0,
  bool originInSoftware = false,
  bool softwareAllApplications = false,
  bool teeAllApplications = false,
  bool corruptSignature = false,
  bool rawStatementSignature = false,
  bool omitAndroidKeyExtension = false,
  List<Object?>? certificateChain,
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
    origin: 'https://example.com',
  );
  final clientDataHash = crypto.sha256.convert(clientDataJson).bytes;
  final effectiveRootKey =
      rootKey ?? _KeyPair.create(privateValue: BigInt.from(0x11));
  final effectiveCertificateKey = certificateKey ?? keyPair;
  final extension =
      extensionOverride ??
      _androidKeyDescription(
        challenge: extensionChallenge ?? clientDataHash,
        includePurpose: includePurpose,
        purposes: purposes,
        purposeInSoftware: purposeInSoftware,
        includeOrigin: includeOrigin,
        origin: origin,
        originInSoftware: originInSoftware,
        softwareAllApplications: softwareAllApplications,
        teeAllApplications: teeAllApplications,
      );
  final rootCertificate = _androidTestCertificate(
    subjectKey: effectiveRootKey,
    issuerKey: effectiveRootKey,
    subjectOrganizationalUnit: 'Android Attestation Root',
    issuerOrganizationalUnit: 'Android Attestation Root',
    isCertificateAuthority: true,
  );
  final leafCertificate = _androidTestCertificate(
    subjectKey: effectiveCertificateKey,
    issuerKey: certificateIssuerKey ?? effectiveRootKey,
    subjectOrganizationalUnit: 'Android Keystore Key',
    issuerOrganizationalUnit: 'Android Attestation Root',
    androidKeyExtension: omitAndroidKeyExtension ? null : extension,
  );
  final derSignature = _signEs256(
    statementSigningKey ?? effectiveCertificateKey,
    <int>[...authData, ...clientDataHash],
  );
  final signature = rawStatementSignature
      ? _rawEs256Signature(derSignature)
      : derSignature;
  if (corruptSignature) signature[signature.length - 1] ^= 0x01;
  final attestationObject = cbor.cbor.encode(<String, Object?>{
    'fmt': 'android-key',
    'authData': authData,
    'attStmt': <String, Object?>{
      'alg': -7,
      'sig': signature,
      'x5c': certificateChain ?? <Object?>[leafCertificate, rootCertificate],
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
      'transports': <String>['internal'],
    },
    'name': 'Android passkey',
  };
}

Map<String, dynamic> _appleRegistrationCredential({
  required String challenge,
  required _KeyPair keyPair,
  _KeyPair? rootKey,
  _KeyPair? certificateKey,
  _KeyPair? certificateIssuerKey,
  List<int>? nonceOverride,
  List<int>? nonceExtensionOverride,
  bool omitNonceExtension = false,
  bool duplicateNonceExtension = false,
  bool rootIsCertificateAuthority = true,
  bool unexpectedStatementField = false,
  bool duplicateX5cField = false,
  List<Object?>? certificateChain,
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
    origin: 'https://example.com',
  );
  final clientDataHash = crypto.sha256.convert(clientDataJson).bytes;
  final nonce =
      nonceOverride ??
      crypto.sha256.convert(<int>[...authData, ...clientDataHash]).bytes;
  final effectiveRootKey =
      rootKey ?? _KeyPair.create(privateValue: BigInt.from(0x31));
  final rootCertificate = _appleTestCertificate(
    subjectKey: effectiveRootKey,
    issuerKey: effectiveRootKey,
    subjectOrganizationalUnit: 'Apple WebAuthn Root',
    issuerOrganizationalUnit: 'Apple WebAuthn Root',
    isCertificateAuthority: rootIsCertificateAuthority,
  );
  final leafCertificate = _appleTestCertificate(
    subjectKey: certificateKey ?? keyPair,
    issuerKey: certificateIssuerKey ?? effectiveRootKey,
    subjectOrganizationalUnit: 'Apple Anonymous Attestation',
    issuerOrganizationalUnit: 'Apple WebAuthn Root',
    nonceExtension: omitNonceExtension
        ? null
        : nonceExtensionOverride ??
              (ASN1Sequence()
                    ..add(ASN1OctetString(octets: Uint8List.fromList(nonce))))
                  .encode(),
    duplicateNonceExtension: duplicateNonceExtension,
  );
  final chain = certificateChain ?? <Object?>[leafCertificate, rootCertificate];
  final statement = <String, Object?>{'x5c': chain};
  if (unexpectedStatementField) statement['receipt'] = <int>[1, 2, 3];
  final attestationObject = duplicateX5cField
      ? Uint8List.fromList(<int>[
          0xa3,
          ...cbor.cbor.encode('fmt'),
          ...cbor.cbor.encode('apple'),
          ...cbor.cbor.encode('authData'),
          ...cbor.cbor.encode(authData),
          ...cbor.cbor.encode('attStmt'),
          0xa2,
          ...cbor.cbor.encode('x5c'),
          ...cbor.cbor.encode(chain),
          ...cbor.cbor.encode('x5c'),
          ...cbor.cbor.encode(chain),
        ])
      : Uint8List.fromList(
          cbor.cbor.encode(<String, Object?>{
            'fmt': 'apple',
            'authData': authData,
            'attStmt': statement,
          }),
        );
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
    'name': 'Apple passkey',
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

Future<FidoMetadataBlob> _loadFidoMetadata({
  required List<int> certificate,
  required List<int> aaguid,
  required String status,
  List<String> previousStatuses = const <String>[],
  List<int>? metadataRoot,
}) async {
  final now = DateTime.utc(2030, 1, 2, 12);
  final encodedAaguid = aaguid
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  final formattedAaguid =
      '${encodedAaguid.substring(0, 8)}-'
      '${encodedAaguid.substring(8, 12)}-'
      '${encodedAaguid.substring(12, 16)}-'
      '${encodedAaguid.substring(16, 20)}-'
      '${encodedAaguid.substring(20)}';
  final header = <String, dynamic>{
    'alg': 'ES256',
    'typ': 'JWT',
    'x5c': <String>[base64.encode(certificate)],
  };
  final payload = <String, dynamic>{
    'legalHeader': 'https://fidoalliance.org/metadata/metadata-legal-terms/',
    'no': 8,
    'nextUpdate': '2030-01-03',
    'entries': <Map<String, dynamic>>[
      <String, dynamic>{
        'aaguid': formattedAaguid,
        'metadataStatement': <String, dynamic>{
          'legalHeader':
              'https://fidoalliance.org/metadata/metadata-statement-legal-header/',
          'description': 'Offline test authenticator',
          'authenticatorVersion': 7,
          'protocolFamily': 'fido2',
          'schema': 3,
          'attestationCertificateKeyIdentifiers': const <String>[],
          'attestationRootCertificates': <String>[
            base64.encode(metadataRoot ?? certificate),
          ],
          'aaguid': formattedAaguid,
        },
        'statusReports': <Map<String, dynamic>>[
          for (final previousStatus in previousStatuses)
            <String, dynamic>{
              'status': previousStatus,
              'effectiveDate': '2029-11-01',
            },
          <String, dynamic>{
            'status': status,
            'effectiveDate': '2029-12-01',
            if (status == 'UPDATE_AVAILABLE') 'authenticatorVersion': 7,
          },
        ],
        'timeOfLastStatusChange': '2029-12-01',
      },
    ],
  };
  final compact = [header, payload]
      .map((value) => base64UrlNoPadding(utf8.encode(jsonEncode(value))))
      .followedBy(<String>[
        base64UrlNoPadding(const <int>[1, 2, 3]),
      ])
      .join('.');
  return FidoMetadataBlobLoader(
    trustAnchors: <List<int>>[certificate],
    verifyJws: (_) => const FidoMetadataJwsVerificationResult.verified(),
  ).load(compact, now: now);
}

Uint8List _packedAttestationCertificate(
  _KeyPair keyPair, {
  String organizationalUnit = 'Authenticator Attestation',
  bool includeBasicConstraints = true,
  List<int>? aaguid,
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
          octets: ASN1OctetString(
            octets: Uint8List.fromList(aaguid ?? List<int>.filled(16, 0)),
          ).encode(),
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
        ..add(ASN1UtcTime(DateTime.utc(2020)))
        ..add(ASN1UtcTime(DateTime.utc(2040))),
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

Uint8List _tpmEcCertificate({
  required _KeyPair subjectKey,
  required _KeyPair issuerKey,
  required ASN1Sequence subject,
  required ASN1Sequence issuer,
  bool isCertificateAuthority = false,
  bool includeBasicConstraints = true,
  bool includeTpmSubjectAlternativeName = false,
  bool criticalTpmSubjectAlternativeName = true,
  bool duplicateTpmSubjectAlternativeName = false,
  bool includeTpmAikExtendedKeyUsage = false,
  List<int>? aaguid,
}) {
  final signatureAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.4.3.2'));
  final publicKeyAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.2.1'))
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.3.1.7'));
  final subjectPublicKeyInfo = ASN1Sequence()
    ..add(publicKeyAlgorithm)
    ..add(
      ASN1BitString(
        stringValues: <int>[0x04, ...subjectKey.x, ...subjectKey.y],
      ),
    );
  final extensions = _tpmCertificateExtensions(
    isCertificateAuthority: isCertificateAuthority,
    includeBasicConstraints: includeBasicConstraints,
    includeSubjectAlternativeName: includeTpmSubjectAlternativeName,
    criticalSubjectAlternativeName: criticalTpmSubjectAlternativeName,
    duplicateSubjectAlternativeName: duplicateTpmSubjectAlternativeName,
    includeAikExtendedKeyUsage: includeTpmAikExtendedKeyUsage,
    aaguid: aaguid,
  );
  final tbsCertificate = ASN1Sequence()
    ..add(_explicitAsn1(0xa0, ASN1Integer(BigInt.two).encode()))
    ..add(ASN1Integer(BigInt.from(80)))
    ..add(signatureAlgorithm)
    ..add(issuer)
    ..add(
      ASN1Sequence()
        ..add(ASN1UtcTime(DateTime.utc(2020)))
        ..add(ASN1UtcTime(DateTime.utc(2040))),
    )
    ..add(subject)
    ..add(subjectPublicKeyInfo)
    ..add(_explicitAsn1(0xa3, extensions.encode()));
  final signature = _signEs256(issuerKey, tbsCertificate.encode());
  return Uint8List.fromList(
    (ASN1Sequence()
          ..add(tbsCertificate)
          ..add(signatureAlgorithm)
          ..add(ASN1BitString(stringValues: signature)))
        .encode(),
  );
}

Uint8List _tpmRsaCertificate({
  required _RsaKeyPair subjectKey,
  required _RsaKeyPair issuerKey,
  required ASN1Sequence subject,
  required ASN1Sequence issuer,
  bool isCertificateAuthority = false,
  bool includeBasicConstraints = true,
  bool includeTpmSubjectAlternativeName = false,
  bool includeTpmAikExtendedKeyUsage = false,
}) {
  final signatureAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.11'))
    ..add(ASN1Null());
  final publicKeyAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'))
    ..add(ASN1Null());
  final rsaPublicKey = ASN1Sequence()
    ..add(ASN1Integer(subjectKey.publicKey.modulus))
    ..add(ASN1Integer(subjectKey.publicKey.publicExponent));
  final subjectPublicKeyInfo = ASN1Sequence()
    ..add(publicKeyAlgorithm)
    ..add(ASN1BitString(stringValues: rsaPublicKey.encode()));
  final extensions = _tpmCertificateExtensions(
    isCertificateAuthority: isCertificateAuthority,
    includeBasicConstraints: includeBasicConstraints,
    includeSubjectAlternativeName: includeTpmSubjectAlternativeName,
    criticalSubjectAlternativeName: true,
    duplicateSubjectAlternativeName: false,
    includeAikExtendedKeyUsage: includeTpmAikExtendedKeyUsage,
  );
  final tbsCertificate = ASN1Sequence()
    ..add(_explicitAsn1(0xa0, ASN1Integer(BigInt.two).encode()))
    ..add(ASN1Integer(BigInt.from(81)))
    ..add(signatureAlgorithm)
    ..add(issuer)
    ..add(
      ASN1Sequence()
        ..add(ASN1UtcTime(DateTime.utc(2020)))
        ..add(ASN1UtcTime(DateTime.utc(2040))),
    )
    ..add(subject)
    ..add(subjectPublicKeyInfo)
    ..add(_explicitAsn1(0xa3, extensions.encode()));
  final signature = _signRs256(issuerKey, tbsCertificate.encode());
  return Uint8List.fromList(
    (ASN1Sequence()
          ..add(tbsCertificate)
          ..add(signatureAlgorithm)
          ..add(ASN1BitString(stringValues: signature)))
        .encode(),
  );
}

ASN1Sequence _tpmCertificateExtensions({
  required bool isCertificateAuthority,
  required bool includeBasicConstraints,
  required bool includeSubjectAlternativeName,
  required bool criticalSubjectAlternativeName,
  required bool duplicateSubjectAlternativeName,
  required bool includeAikExtendedKeyUsage,
  List<int>? aaguid,
}) {
  final extensions = ASN1Sequence();
  if (includeBasicConstraints) {
    final basicConstraints = ASN1Sequence();
    if (isCertificateAuthority) basicConstraints.add(ASN1Boolean(true));
    extensions.add(
      ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.19'))
        ..add(ASN1Boolean(true))
        ..add(ASN1OctetString(octets: basicConstraints.encode())),
    );
  }
  if (includeSubjectAlternativeName) {
    ASN1Sequence extension() {
      final directoryName = ASN1Sequence()
        ..add(_tpmNameAttribute('2.23.133.2.1', 'id:4D534654'))
        ..add(_tpmNameAttribute('2.23.133.2.2', 'Routed TPM'))
        ..add(_tpmNameAttribute('2.23.133.2.3', 'id:00010001'));
      final generalNames = ASN1Sequence()
        ..add(_explicitAsn1(0xa4, directoryName.encode()));
      return ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.17'))
        ..add(ASN1Boolean(criticalSubjectAlternativeName))
        ..add(ASN1OctetString(octets: generalNames.encode()));
    }

    extensions.add(extension());
    if (duplicateSubjectAlternativeName) extensions.add(extension());
  }
  if (includeAikExtendedKeyUsage) {
    final usage = ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromIdentifierString('2.23.133.8.3'));
    extensions.add(
      ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.37'))
        ..add(ASN1OctetString(octets: usage.encode())),
    );
  }
  if (aaguid != null) {
    extensions.add(
      ASN1Sequence()
        ..add(
          ASN1ObjectIdentifier.fromIdentifierString('1.3.6.1.4.1.45724.1.1.4'),
        )
        ..add(
          ASN1OctetString(
            octets: ASN1OctetString(
              octets: Uint8List.fromList(aaguid),
            ).encode(),
          ),
        ),
    );
  }
  return extensions;
}

ASN1Set _tpmNameAttribute(String identifier, String value) => ASN1Set()
  ..add(
    ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromIdentifierString(identifier))
      ..add(ASN1UTF8String(utf8StringValue: value)),
  );

Uint8List _androidKeyDescription({
  required List<int> challenge,
  bool includePurpose = true,
  Set<int> purposes = const <int>{2},
  bool purposeInSoftware = false,
  bool includeOrigin = true,
  int origin = 0,
  bool originInSoftware = false,
  bool softwareAllApplications = false,
  bool teeAllApplications = false,
}) {
  Uint8List authorizationList({required bool software}) {
    final fields = <int>[];
    if (includePurpose && purposeInSoftware == software) {
      final purposeSet = ASN1Set();
      for (final purpose in purposes.toList()..sort()) {
        purposeSet.add(ASN1Integer(BigInt.from(purpose)));
      }
      fields.addAll(_derExplicitContext(1, purposeSet.encode()));
    }
    if ((software && softwareAllApplications) ||
        (!software && teeAllApplications)) {
      fields.addAll(_derExplicitContext(600, ASN1Null().encode()));
    }
    if (includeOrigin && originInSoftware == software) {
      fields.addAll(
        _derExplicitContext(702, ASN1Integer(BigInt.from(origin)).encode()),
      );
    }
    return _derValue(<int>[0x30], fields);
  }

  return _derValue(
    <int>[0x30],
    <int>[
      ...ASN1Integer(BigInt.from(300)).encode(),
      ...ASN1Integer(BigInt.one, tag: 0x0a).encode(),
      ...ASN1Integer(BigInt.from(300)).encode(),
      ...ASN1Integer(BigInt.one, tag: 0x0a).encode(),
      ...ASN1OctetString(octets: Uint8List.fromList(challenge)).encode(),
      ...ASN1OctetString(octets: Uint8List(0)).encode(),
      ...authorizationList(software: true),
      ...authorizationList(software: false),
    ],
  );
}

Uint8List _androidTestCertificate({
  required _KeyPair subjectKey,
  required _KeyPair issuerKey,
  required String subjectOrganizationalUnit,
  required String issuerOrganizationalUnit,
  bool isCertificateAuthority = false,
  List<int>? androidKeyExtension,
}) {
  final signatureAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.4.3.2'));
  final subject = _certificateName(subjectOrganizationalUnit);
  final issuer = _certificateName(issuerOrganizationalUnit);
  final publicKeyAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.2.1'))
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.3.1.7'));
  final subjectPublicKeyInfo = ASN1Sequence()
    ..add(publicKeyAlgorithm)
    ..add(
      ASN1BitString(
        stringValues: <int>[0x04, ...subjectKey.x, ...subjectKey.y],
      ),
    );
  final basicConstraints = ASN1Sequence();
  if (isCertificateAuthority) basicConstraints.add(ASN1Boolean(true));
  final extensions = ASN1Sequence()
    ..add(
      ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.19'))
        ..add(ASN1Boolean(true))
        ..add(ASN1OctetString(octets: basicConstraints.encode())),
    );
  if (androidKeyExtension != null) {
    extensions.add(
      ASN1Sequence()
        ..add(
          ASN1ObjectIdentifier.fromIdentifierString('1.3.6.1.4.1.11129.2.1.17'),
        )
        ..add(ASN1OctetString(octets: Uint8List.fromList(androidKeyExtension))),
    );
  }
  final tbsCertificate = ASN1Sequence()
    ..add(_explicitAsn1(0xa0, ASN1Integer(BigInt.two).encode()))
    ..add(ASN1Integer(BigInt.from(androidKeyExtension == null ? 20 : 21)))
    ..add(signatureAlgorithm)
    ..add(issuer)
    ..add(
      ASN1Sequence()
        ..add(ASN1UtcTime(DateTime.utc(2020)))
        ..add(ASN1UtcTime(DateTime.utc(2040))),
    )
    ..add(subject)
    ..add(subjectPublicKeyInfo)
    ..add(_explicitAsn1(0xa3, extensions.encode()));
  final signature = _signEs256(issuerKey, tbsCertificate.encode());
  return Uint8List.fromList(
    (ASN1Sequence()
          ..add(tbsCertificate)
          ..add(signatureAlgorithm)
          ..add(ASN1BitString(stringValues: signature)))
        .encode(),
  );
}

Uint8List _appleTestCertificate({
  required _KeyPair subjectKey,
  required _KeyPair issuerKey,
  required String subjectOrganizationalUnit,
  required String issuerOrganizationalUnit,
  bool isCertificateAuthority = false,
  List<int>? nonceExtension,
  bool duplicateNonceExtension = false,
}) {
  final signatureAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.4.3.2'));
  final subject = _certificateName(subjectOrganizationalUnit);
  final issuer = _certificateName(issuerOrganizationalUnit);
  final publicKeyAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.2.1'))
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.3.1.7'));
  final subjectPublicKeyInfo = ASN1Sequence()
    ..add(publicKeyAlgorithm)
    ..add(
      ASN1BitString(
        stringValues: <int>[0x04, ...subjectKey.x, ...subjectKey.y],
      ),
    );
  final basicConstraints = ASN1Sequence();
  if (isCertificateAuthority) basicConstraints.add(ASN1Boolean(true));
  final extensions = ASN1Sequence()
    ..add(
      ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromIdentifierString('2.5.29.19'))
        ..add(ASN1Boolean(true))
        ..add(ASN1OctetString(octets: basicConstraints.encode())),
    );
  if (nonceExtension != null) {
    ASN1Sequence extension() => ASN1Sequence()
      ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113635.100.8.2'))
      ..add(ASN1OctetString(octets: Uint8List.fromList(nonceExtension)));

    extensions.add(extension());
    if (duplicateNonceExtension) extensions.add(extension());
  }
  final tbsCertificate = ASN1Sequence()
    ..add(_explicitAsn1(0xa0, ASN1Integer(BigInt.two).encode()))
    ..add(ASN1Integer(BigInt.from(nonceExtension == null ? 40 : 41)))
    ..add(signatureAlgorithm)
    ..add(issuer)
    ..add(
      ASN1Sequence()
        ..add(ASN1UtcTime(DateTime.utc(2020)))
        ..add(ASN1UtcTime(DateTime.utc(2040))),
    )
    ..add(subject)
    ..add(subjectPublicKeyInfo)
    ..add(_explicitAsn1(0xa3, extensions.encode()));
  final signature = _signEs256(issuerKey, tbsCertificate.encode());
  return Uint8List.fromList(
    (ASN1Sequence()
          ..add(tbsCertificate)
          ..add(signatureAlgorithm)
          ..add(ASN1BitString(stringValues: signature)))
        .encode(),
  );
}

Uint8List _derExplicitContext(int tagNumber, List<int> value) {
  final identifier = <int>[0xa0];
  if (tagNumber < 31) {
    identifier[0] |= tagNumber;
  } else {
    identifier[0] |= 0x1f;
    final encodedTag = <int>[tagNumber & 0x7f];
    var remaining = tagNumber >> 7;
    while (remaining != 0) {
      encodedTag.insert(0, 0x80 | (remaining & 0x7f));
      remaining >>= 7;
    }
    identifier.addAll(encodedTag);
  }
  return _derValue(identifier, value);
}

Uint8List _derValue(List<int> identifier, List<int> value) {
  final length = <int>[];
  if (value.length < 128) {
    length.add(value.length);
  } else {
    final encodedLength = <int>[];
    var remaining = value.length;
    while (remaining != 0) {
      encodedLength.insert(0, remaining & 0xff);
      remaining >>= 8;
    }
    length
      ..add(0x80 | encodedLength.length)
      ..addAll(encodedLength);
  }
  return Uint8List.fromList(<int>[...identifier, ...length, ...value]);
}

Uint8List _packedRsaAttestationCertificate(_RsaKeyPair keyPair) {
  final signatureAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.11'))
    ..add(ASN1Null());
  final publicKeyAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'))
    ..add(ASN1Null());
  final rsaPublicKey = ASN1Sequence()
    ..add(ASN1Integer(keyPair.publicKey.modulus))
    ..add(ASN1Integer(keyPair.publicKey.publicExponent));
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
        ..add(ASN1UtcTime(DateTime.utc(2020)))
        ..add(ASN1UtcTime(DateTime.utc(2040))),
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
