import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/asn1.dart';
import 'package:property_testing/property_testing.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  group('FIDO Metadata Service source', () {
    late Uint8List certificate;
    late DateTime now;

    setUp(() {
      certificate = _testCertificate();
      now = DateTime.utc(2030, 1, 2, 12);
    });

    test(
      'loads a browser-shaped compact MDS3 fixture after JWS verification',
      () async {
        var verifierCalls = 0;
        final loader = FidoMetadataBlobLoader(
          trustAnchors: <List<int>>[certificate],
          verifyJws: (input) {
            verifierCalls++;
            final expected = crypto.sha256
                .convert(utf8.encode(input.signingInput))
                .bytes;
            return expected.length == input.signatureBytes.length &&
                    _sameBytes(expected, input.signatureBytes) &&
                    input.algorithm == 'ES256' &&
                    input.certificateChain.length == 1 &&
                    _sameBytes(input.certificateChain.single, certificate) &&
                    input.trustAnchors.length == 1
                ? const FidoMetadataJwsVerificationResult.verified()
                : const FidoMetadataJwsVerificationResult.rejected();
          },
        );
        final blob = await loader.load(
          _compactBlob(
            certificate: certificate,
            now: now,
            aaguid: '0132d110bf4e4208a403ab4f5f12efe5',
          ),
          now: now,
        );

        expect(verifierCalls, 1);
        expect(blob.number, 1234);
        expect(blob.algorithm, 'ES256');
        expect(blob.issuedAt, isNull);
        expect(blob.verifiedAt, now);
        expect(blob.nextUpdate, DateTime.utc(2030, 1, 3));
        expect(blob.entries, hasLength(1));
        expect(
          blob.entries.single.aaguid,
          '0132d110-bf4e-4208-a403-ab4f5f12efe5',
        );
        expect(
          blob.entries.single.metadataStatement.attestationRootCertificates,
          hasLength(1),
        );
      },
    );

    test('loads the live official RS256 header shape without iat', () async {
      final intermediate = _testCertificate(marker: 2);
      var verifierCalls = 0;
      final loader = FidoMetadataBlobLoader(
        trustAnchors: <List<int>>[certificate],
        verifyJws: (input) {
          verifierCalls++;
          return input.algorithm == 'RS256' &&
                  input.certificateChain.length == 2 &&
                  _sameBytes(input.certificateChain.first, certificate) &&
                  _sameBytes(input.certificateChain.last, intermediate)
              ? const FidoMetadataJwsVerificationResult.verified()
              : const FidoMetadataJwsVerificationResult.rejected();
        },
      );
      final header = jsonEncode(<String, dynamic>{
        'alg': 'RS256',
        'typ': 'JWT',
        'x5c': <String>[
          base64.encode(certificate),
          base64.encode(intermediate),
        ],
      });

      final blob = await loader.load(
        _compactFromJson(
          header,
          _payload(certificate: certificate, now: now, number: 277),
        ),
        now: now,
      );

      expect(verifierCalls, 1);
      expect(blob.number, 277);
      expect(blob.algorithm, 'RS256');
      expect(blob.issuedAt, isNull);
      expect(blob.nextUpdate, DateTime.utc(2030, 1, 3));
    });

    test(
      'rejects tampered signatures and unsafe algorithms before trust',
      () async {
        final calls = <FidoMetadataJwsVerificationInput>[];
        final loader = _loader(
          certificate,
          verifier: (input) {
            calls.add(input);
            return const FidoMetadataJwsVerificationResult.rejected();
          },
        );
        await expectLater(
          loader.load(
            _compactBlob(
              certificate: certificate,
              now: now,
              signature: const <int>[1, 2, 3],
            ),
            now: now,
          ),
          throwsA(isA<FidoMetadataException>()),
        );
        expect(calls, hasLength(1));

        await expectLater(
          loader.load(
            _compactBlob(certificate: certificate, now: now, algorithm: 'none'),
            now: now,
          ),
          throwsA(isA<FidoMetadataException>()),
        );
        expect(calls, hasLength(1));

        await expectLater(
          loader.load(
            _compactBlob(
              certificate: certificate,
              now: now,
              algorithm: 'HS256',
            ),
            now: now,
          ),
          throwsA(isA<FidoMetadataException>()),
        );
        expect(calls, hasLength(1));

        await expectLater(
          loader.load(
            _compactFromJson(
              '{"alg":"ES256","iat":1893456000,"x5u":"https://example.com/mds-chain"}',
              _payload(certificate: certificate, now: now),
            ),
            now: now,
          ),
          throwsA(isA<FidoMetadataException>()),
        );
        expect(calls, hasLength(1));
      },
    );

    test('uses configured signing anchors when x5c is absent', () async {
      var verifierCalls = 0;
      final loader = FidoMetadataBlobLoader(
        trustAnchors: <List<int>>[certificate],
        verifyJws: (input) {
          verifierCalls++;
          return input.certificateChain.length == 1 &&
                  _sameBytes(input.certificateChain.single, certificate)
              ? const FidoMetadataJwsVerificationResult.verified()
              : const FidoMetadataJwsVerificationResult.rejected();
        },
      );

      final blob = await loader.load(
        _compactFromJson(
          _headerJson(),
          _payload(certificate: certificate, now: now),
        ),
        now: now,
      );

      expect(verifierCalls, 1);
      expect(blob.verifiedAt, now);
      expect(blob.issuedAt, isNull);
    });

    test(
      'rejects duplicate JSON keys, zip confusion, and malformed dates',
      () async {
        final loader = _loader(certificate);
        final payload = _payload(certificate: certificate, now: now);
        final duplicateHeader = _compactFromJson(
          '{"alg":"ES256","alg":"RS256","iat":1893456000}',
          payload,
        );
        for (final value in <String>[
          duplicateHeader,
          'PK\\x03\\x04',
          _compactFromJson(_headerJson(), <String, dynamic>{
            ...payload,
            'nextUpdate': '2030-02-31',
          }),
        ]) {
          await expectLater(
            loader.load(value, now: now),
            throwsA(isA<FidoMetadataException>()),
          );
        }
      },
    );

    test('rejects stale, future, and non-increasing payload numbers', () async {
      final loader = _loader(certificate);
      final strictFreshnessLoader = FidoMetadataBlobLoader(
        trustAnchors: <List<int>>[certificate],
        nextUpdatePolicy: FidoMetadataNextUpdatePolicy.requireFreshWhenPresent,
        verifyJws: (_) => const FidoMetadataJwsVerificationResult.verified(),
      );
      await expectLater(
        strictFreshnessLoader.load(
          _compactBlob(
            certificate: certificate,
            now: now,
            nextUpdate: '2030-01-02T12:00:00Z',
          ),
          now: now,
        ),
        throwsA(isA<FidoMetadataException>()),
      );
      await expectLater(
        loader.load(
          _compactBlob(
            certificate: certificate,
            now: now,
            issuedAt: DateTime.utc(2030, 1, 3),
          ),
          now: now,
        ),
        throwsA(isA<FidoMetadataException>()),
      );
      await expectLater(
        loader.load(
          _compactBlob(certificate: certificate, now: now),
          now: now,
          previousBlobNumber: 1234,
        ),
        throwsA(isA<FidoMetadataException>()),
      );
      await expectLater(
        loader.load(
          _compactBlob(certificate: certificate, now: now, number: 1234),
          now: now,
          previousBlobNumber: 1234,
        ),
        throwsA(isA<FidoMetadataException>()),
      );

      final skippedSerial = await loader.load(
        _compactBlob(certificate: certificate, now: now, number: 1236),
        now: now,
        previousBlobNumber: 1234,
      );
      expect(skippedSerial.number, 1236);
    });

    test('accepts a future-compatible blob without nextUpdate', () async {
      final blob = await _loader(certificate).load(
        _compactBlob(certificate: certificate, now: now, nextUpdate: null),
        now: now,
      );

      expect(blob.nextUpdate, isNull);
      expect(blob.issuedAt, isNull);
      expect(blob.verifiedAt, now);
    });

    test('rejects duplicate AAGUIDs and malformed metadata roots', () async {
      final loader = _loader(certificate);
      final payload = _payload(certificate: certificate, now: now);
      final duplicateEntries = <String, dynamic>{
        ...payload,
        'entries': <Object?>[
          ((payload['entries'] as List).single as Map<String, dynamic>),
          ((payload['entries'] as List).single as Map<String, dynamic>),
        ],
      };
      await expectLater(
        loader.load(
          _compactFromJson(_headerJson(), duplicateEntries),
          now: now,
        ),
        throwsA(isA<FidoMetadataException>()),
      );

      final malformedRootStatement = <String, dynamic>{
        ...payload,
        'entries': <Object?>[
          <String, dynamic>{
            ...(payload['entries'] as List).single as Map<String, dynamic>,
            'metadataStatement': <String, dynamic>{
              ...((payload['entries'] as List).single
                      as Map<String, dynamic>)['metadataStatement']
                  as Map<String, dynamic>,
              'attestationRootCertificates': <String>['AQI='],
            },
          },
        ],
      };
      await expectLater(
        loader.load(
          _compactFromJson(_headerJson(), malformedRootStatement),
          now: now,
        ),
        throwsA(isA<FidoMetadataException>()),
      );
    });

    test('property rejects every over-bound compact JWT segment', () async {
      final loader = FidoMetadataBlobLoader(
        trustAnchors: <List<int>>[certificate],
        limits: const FidoMetadataLimits(
          maxBlobBytes: 256,
          maxJwtSegmentBytes: 16,
        ),
        verifyJws: (_) => const FidoMetadataJwsVerificationResult.verified(),
      );
      final runner = PropertyTestRunner<int>(Gen.integer(min: 17, max: 64), (
        length,
      ) async {
        await expectLater(
          loader.load('${'a' * length}.e.s', now: now),
          throwsA(isA<FidoMetadataException>()),
        );
      }, PropertyConfig(numTests: 20, seed: 20300102));
      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    });

    test('property rejects malformed bounded compact inputs', () async {
      final loader = _loader(certificate);
      final runner = PropertyTestRunner<String>(
        Chaos.string(minLength: 0, maxLength: 512),
        (value) async {
          await expectLater(
            loader.load(value, now: now),
            throwsA(isA<FidoMetadataException>()),
          );
        },
        PropertyConfig(numTests: 500, seed: 20300103),
      );
      final result = await runner.run();
      expect(result.success, isTrue, reason: _propertyReport(result));
    });

    test('live-sized defaults retain bounded headroom', () {
      const limits = FidoMetadataLimits();
      expect(limits.maxBlobBytes, greaterThan(10_446_034));
      expect(limits.maxBlobBytes, lessThanOrEqualTo(32 * 1024 * 1024));
      expect(limits.maxJwtSegmentBytes, 24 * 1024 * 1024);
    });

    test('enforces exact configured blob and segment boundaries', () async {
      final compact = _compactBlob(certificate: certificate, now: now);
      final segments = compact.split('.');
      final longestSegment = segments
          .map((segment) => segment.length)
          .reduce((first, second) => first > second ? first : second);

      final exact = FidoMetadataBlobLoader(
        trustAnchors: <List<int>>[certificate],
        limits: FidoMetadataLimits(
          maxBlobBytes: compact.length,
          maxJwtSegmentBytes: longestSegment,
        ),
        verifyJws: (_) => const FidoMetadataJwsVerificationResult.verified(),
      );
      expect((await exact.load(compact, now: now)).number, 1234);

      for (final limits in <FidoMetadataLimits>[
        FidoMetadataLimits(
          maxBlobBytes: compact.length - 1,
          maxJwtSegmentBytes: longestSegment,
        ),
        FidoMetadataLimits(
          maxBlobBytes: compact.length,
          maxJwtSegmentBytes: longestSegment - 1,
        ),
      ]) {
        await expectLater(
          FidoMetadataBlobLoader(
            trustAnchors: <List<int>>[certificate],
            limits: limits,
            verifyJws: (_) =>
                const FidoMetadataJwsVerificationResult.verified(),
          ).load(compact, now: now),
          throwsA(isA<FidoMetadataException>()),
        );
      }
    });
  });
}

FidoMetadataBlobLoader _loader(
  List<int> certificate, {
  FidoMetadataJwsVerifier? verifier,
}) => FidoMetadataBlobLoader(
  trustAnchors: <List<int>>[certificate],
  verifyJws:
      verifier ?? (_) => const FidoMetadataJwsVerificationResult.verified(),
);

String _compactBlob({
  required List<int> certificate,
  required DateTime now,
  DateTime? issuedAt,
  String? nextUpdate = '2030-01-03',
  int number = 1234,
  String aaguid = '0132d110bf4e4208a403ab4f5f12efe5',
  String algorithm = 'ES256',
  List<int>? signature,
}) {
  final header = _headerJson(
    issuedAt: issuedAt,
    algorithm: algorithm,
    certificate: certificate,
  );
  final payload = _payload(
    certificate: certificate,
    now: now,
    number: number,
    nextUpdate: nextUpdate,
    aaguid: aaguid,
  );
  final signingInput =
      '${_b64(utf8.encode(header))}.${_b64(utf8.encode(jsonEncode(payload)))}';
  final signedBytes =
      signature ?? crypto.sha256.convert(utf8.encode(signingInput)).bytes;
  return _compactFromJson(header, payload, signature: signedBytes);
}

String _compactFromJson(
  String header,
  Map<String, dynamic> payload, {
  List<int> signature = const <int>[1, 2, 3],
}) =>
    '${_b64(utf8.encode(header))}.${_b64(utf8.encode(jsonEncode(payload)))}.${_b64(signature)}';

String _headerJson({
  DateTime? issuedAt,
  String algorithm = 'ES256',
  List<int>? certificate,
}) => jsonEncode(<String, dynamic>{
  'alg': algorithm,
  'typ': 'JWT',
  if (issuedAt != null) 'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
  if (certificate != null) 'x5c': <String>[base64.encode(certificate)],
});

Map<String, dynamic> _payload({
  required List<int> certificate,
  required DateTime now,
  int number = 1234,
  String? nextUpdate = '2030-01-03',
  String aaguid = '0132d110bf4e4208a403ab4f5f12efe5',
}) => <String, dynamic>{
  'legalHeader': 'https://fidoalliance.org/metadata/metadata-legal-terms/',
  'no': number,
  'nextUpdate': ?nextUpdate,
  'entries': <Map<String, dynamic>>[
    <String, dynamic>{
      'aaguid': aaguid,
      'metadataStatement': <String, dynamic>{
        'legalHeader':
            'https://fidoalliance.org/metadata/metadata-statement-legal-header/',
        'description': 'Example browser authenticator',
        'authenticatorVersion': 7,
        'protocolFamily': 'fido2',
        'schema': 3,
        'attestationCertificateKeyIdentifiers': const <String>[],
        'attestationRootCertificates': <String>[base64.encode(certificate)],
        'aaguid': aaguid,
      },
      'statusReports': <Map<String, dynamic>>[
        <String, dynamic>{
          'status': 'FIDO_CERTIFIED',
          'effectiveDate': '2029-12-01',
        },
      ],
      'timeOfLastStatusChange': '2029-12-01',
    },
  ],
};

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _testCertificate({int marker = 1}) {
  final signatureAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.4.3.2'));
  final publicKeyAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.2.1'))
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.3.1.7'));
  final subjectPublicKeyInfo = ASN1Sequence()
    ..add(publicKeyAlgorithm)
    ..add(
      ASN1BitString(stringValues: <int>[0x04, ...List<int>.filled(64, marker)])
        ..unusedbits = 0,
    );
  final tbs = ASN1Sequence()
    ..add(ASN1Integer(BigInt.from(marker)))
    ..add(signatureAlgorithm)
    ..add(ASN1Sequence())
    ..add(ASN1Sequence())
    ..add(ASN1Sequence())
    ..add(subjectPublicKeyInfo);
  return (ASN1Sequence()
        ..add(tbs)
        ..add(signatureAlgorithm)
        ..add(ASN1BitString(stringValues: <int>[1])..unusedbits = 0))
      .encode();
}

bool _sameBytes(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

String _propertyReport(PropertyResult result) {
  if (result.success) return 'All ${result.numTests} generated cases passed';
  return 'Property failed: ${result.error}; input=${result.failingInput}; seed=${result.seed}';
}
