import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart' as cbor;
import 'package:crypto/crypto.dart' as crypto;
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
  _Fixture() {
    provider = WebAuthnProvider(
      getUserInfo: (_, _, _) => null,
      getRelyingParty: (_, _) => const WebAuthnRelyingParty(
        id: 'example.com',
        name: 'Example',
        origin: 'https://example.com',
      ),
    );
    store = InMemoryAuthStore();
    user = AuthUser(
      id: 'user-1',
      email: 'user@example.com',
      name: 'Example User',
    );
    feature = WebAuthnFeature<Object>(provider: provider);
    AuthRuntime<Object>(
      options: AuthOptions<Object>(
        providers: [provider],
        store: store,
        storeMode: AuthStoreMode.ephemeral,
        features: [feature],
      ),
    );
  }

  late final WebAuthnProvider provider;
  late final InMemoryAuthStore store;
  late final AuthUser user;
  late final WebAuthnFeature<Object> feature;
  final Object context = Object();
  final _KeyPair keyPair = _KeyPair.create();
}

final class _RecordingSessionControl implements AuthFeatureSessionControl {
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
    test('registers an ES256 passkey and authenticates it', () async {
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
    });

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

Map<String, dynamic> _registrationCredential({
  required String challenge,
  required _KeyPair keyPair,
  String origin = 'https://example.com',
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
  final attestationObject = cbor.cbor.encode(<String, Object?>{
    'fmt': 'none',
    'authData': authData,
    'attStmt': <String, Object?>{},
  });
  final clientDataJson = _clientData(
    type: 'webauthn.create',
    challenge: challenge,
    origin: origin,
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
    'name': 'Laptop',
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
  return Uint8List.fromList(<int>[
    ..._bigIntBytes(signature.r, 32),
    ..._bigIntBytes(signature.s, 32),
  ]);
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
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(keyPair.privateKey));
  final signature = signer.generateSignature(Uint8List.fromList(signedData));
  return <String, dynamic>{
    'id': credentialId,
    'rawId': credentialId,
    'type': 'public-key',
    'response': <String, dynamic>{
      'clientDataJSON': base64UrlNoPadding(clientDataJson),
      'authenticatorData': base64UrlNoPadding(authenticatorData),
      'signature': base64UrlNoPadding(signature.bytes),
    },
  };
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

final class _KeyPair {
  _KeyPair._({required this.privateKey, required this.x, required this.y});

  factory _KeyPair.create() {
    final parameters = ECDomainParameters('secp256r1');
    final privateValue = BigInt.one;
    final point = (parameters.G * privateValue)!;
    return _KeyPair._(
      privateKey: ECPrivateKey(privateValue, parameters),
      x: Uint8List.fromList(_bigIntBytes(point.x!.toBigInteger()!, 32)),
      y: Uint8List.fromList(_bigIntBytes(point.y!.toBigInteger()!, 32)),
    );
  }

  final ECPrivateKey privateKey;
  final Uint8List x;
  final Uint8List y;
}

final class _RsaKeyPair {
  _RsaKeyPair._({required this.privateKey, required this.cosePublicKey});

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
  final Uint8List cosePublicKey;
}
