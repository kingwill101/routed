import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart' as cbor;
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// Deterministic browser-shaped ES256 WebAuthn ceremony payloads.
///
/// This fixture is test support only. It models `PublicKeyCredential.toJSON()`
/// values while retaining the private key needed to sign assertions. It never
/// contacts a browser, authenticator, metadata service, or network endpoint.
final class AuthWebAuthnCeremonyFixture {
  /// Creates a deterministic platform-passkey fixture for one relying party.
  AuthWebAuthnCeremonyFixture({
    required this.relyingPartyId,
    required Uri origin,
    this.credentialName = 'Runtime platform passkey',
  }) : origin = origin.origin,
       _keyPair = _Es256KeyPair.create();

  /// RP ID hashed into authenticator data.
  final String relyingPartyId;

  /// Browser origin serialized into collected client data.
  final String origin;

  /// Routed passkey label carried beside the browser credential JSON.
  final String credentialName;

  final _Es256KeyPair _keyPair;

  static final Uint8List _credentialBytes = Uint8List.fromList(
    List<int>.generate(16, (index) => index + 1),
  );

  /// Stable base64url credential ID used by both ceremonies.
  String get credentialId => _base64Url(_credentialBytes);

  /// Builds a browser-shaped registration credential for [challenge].
  Map<String, dynamic> registrationCredential({required String challenge}) {
    final coseKey = cbor.cbor.encode(<Object?, Object?>{
      1: 2,
      3: -7,
      -1: 1,
      -2: _keyPair.x.toList(growable: false),
      -3: _keyPair.y.toList(growable: false),
    });
    final authenticatorData = <int>[
      ...crypto.sha256.convert(utf8.encode(relyingPartyId)).bytes,
      0x45,
      0,
      0,
      0,
      0,
      ...List<int>.filled(16, 0),
      _credentialBytes.length >> 8,
      _credentialBytes.length & 0xff,
      ..._credentialBytes,
      ...coseKey,
    ];
    final attestationObject = cbor.cbor.encode(<String, Object?>{
      'fmt': 'none',
      'authData': authenticatorData,
      'attStmt': <String, Object?>{},
    });
    return <String, dynamic>{
      'id': credentialId,
      'rawId': credentialId,
      'type': 'public-key',
      'authenticatorAttachment': 'platform',
      'clientExtensionResults': <String, Object?>{},
      'response': <String, dynamic>{
        'clientDataJSON': _base64Url(
          _clientData(type: 'webauthn.create', challenge: challenge),
        ),
        'attestationObject': _base64Url(attestationObject),
        'transports': <String>['internal'],
      },
      'name': credentialName,
    };
  }

  /// Builds a browser-shaped assertion with an ASN.1 DER ES256 signature.
  Map<String, dynamic> assertionCredential({
    required String challenge,
    required int counter,
    String? userHandle,
  }) {
    final authenticatorData = <int>[
      ...crypto.sha256.convert(utf8.encode(relyingPartyId)).bytes,
      0x05,
      (counter >> 24) & 0xff,
      (counter >> 16) & 0xff,
      (counter >> 8) & 0xff,
      counter & 0xff,
    ];
    final clientDataJson = _clientData(
      type: 'webauthn.get',
      challenge: challenge,
    );
    final signature = _keyPair.sign(<int>[
      ...authenticatorData,
      ...crypto.sha256.convert(clientDataJson).bytes,
    ]);
    return <String, dynamic>{
      'id': credentialId,
      'rawId': credentialId,
      'type': 'public-key',
      'authenticatorAttachment': 'platform',
      'clientExtensionResults': <String, Object?>{},
      'response': <String, dynamic>{
        'clientDataJSON': _base64Url(clientDataJson),
        'authenticatorData': _base64Url(authenticatorData),
        'signature': _base64Url(signature),
        'userHandle': userHandle,
      },
    };
  }

  /// Whether [credential] contains a structurally complete DER sequence.
  bool hasDerEs256Signature(Map<String, dynamic> credential) {
    final response = credential['response'];
    if (response is! Map || response['signature'] is! String) return false;
    try {
      final bytes = _decodeBase64Url(response['signature'] as String);
      if (bytes.length < 8 ||
          bytes.first != 0x30 ||
          bytes[1] != bytes.length - 2 ||
          bytes[2] != 0x02) {
        return false;
      }
      final rLength = bytes[3];
      final sTag = 4 + rLength;
      if (rLength < 1 ||
          rLength > 33 ||
          sTag + 2 > bytes.length ||
          bytes[sTag] != 0x02) {
        return false;
      }
      final sLength = bytes[sTag + 1];
      return sLength >= 1 &&
          sLength <= 33 &&
          sTag + 2 + sLength == bytes.length;
    } on FormatException {
      return false;
    }
  }

  Uint8List _clientData({required String type, required String challenge}) =>
      Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'type': type,
            'challenge': challenge,
            'origin': origin,
            'crossOrigin': false,
          }),
        ),
      );
}

final class _Es256KeyPair {
  const _Es256KeyPair({
    required this.privateKey,
    required this.x,
    required this.y,
  });

  factory _Es256KeyPair.create() {
    final parameters = ECDomainParameters('secp256r1');
    final point = (parameters.G * BigInt.one)!;
    return _Es256KeyPair(
      privateKey: ECPrivateKey(BigInt.one, parameters),
      x: Uint8List.fromList(_bigIntBytes(point.x!.toBigInteger()!, 32)),
      y: Uint8List.fromList(_bigIntBytes(point.y!.toBigInteger()!, 32)),
    );
  }

  final ECPrivateKey privateKey;
  final Uint8List x;
  final Uint8List y;

  Uint8List sign(List<int> message) {
    final random = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(List<int>.generate(32, (index) => index + 1)),
        ),
      );
    final signer = ECDSASigner(SHA256Digest())
      ..init(
        true,
        ParametersWithRandom(
          PrivateKeyParameter<ECPrivateKey>(privateKey),
          random,
        ),
      );
    final signature = signer.generateSignature(Uint8List.fromList(message));
    if (signature is! ECSignature) {
      throw StateError('Expected an ECDSA test signature.');
    }
    final r = _derInteger(signature.r);
    final s = _derInteger(signature.s);
    return Uint8List.fromList(<int>[0x30, r.length + s.length, ...r, ...s]);
  }
}

List<int> _derInteger(BigInt value) {
  var bytes = _bigIntBytes(value, 32);
  while (bytes.length > 1 && bytes.first == 0) {
    bytes = bytes.sublist(1);
  }
  if (bytes.first & 0x80 != 0) bytes = <int>[0, ...bytes];
  return <int>[0x02, bytes.length, ...bytes];
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

String _base64Url(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

Uint8List _decodeBase64Url(String value) {
  final normalized = value.padRight((value.length + 3) ~/ 4 * 4, '=');
  return Uint8List.fromList(base64Url.decode(normalized));
}
