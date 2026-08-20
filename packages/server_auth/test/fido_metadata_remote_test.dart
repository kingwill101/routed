import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:server_auth/server_auth.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2030, 1, 2, 12);
  late _EcKey rootKey;
  late _EcKey intermediateKey;
  late _EcKey leafKey;
  late _RsaKey rsaLeafKey;
  late Uint8List root;
  late Uint8List intermediate;
  late Uint8List leaf;
  late Uint8List rsaLeaf;

  setUpAll(() {
    rootKey = _EcKey.create(BigInt.one);
    intermediateKey = _EcKey.create(BigInt.two);
    leafKey = _EcKey.create(BigInt.from(3));
    rsaLeafKey = _RsaKey.create();
    root = _certificate(
      subjectKey: rootKey,
      issuerKey: rootKey,
      subjectName: 'MDS Root',
      issuerName: 'MDS Root',
      serial: 1,
      isCertificateAuthority: true,
      keyUsage: 0x06,
      pathLength: 2,
    );
    intermediate = _certificate(
      subjectKey: intermediateKey,
      issuerKey: rootKey,
      subjectName: 'MDS Intermediate',
      issuerName: 'MDS Root',
      serial: 2,
      isCertificateAuthority: true,
      keyUsage: 0x06,
      pathLength: 0,
    );
    leaf = _certificate(
      subjectKey: leafKey,
      issuerKey: intermediateKey,
      subjectName: 'MDS Signer',
      issuerName: 'MDS Intermediate',
      serial: 3,
      keyUsage: 0x80,
      extendedKeyUsages: const <String>[
        '1.3.6.1.5.5.7.3.1',
        '1.3.6.1.5.5.7.3.2',
      ],
    );
    rsaLeaf = _certificate(
      subjectKey: rsaLeafKey,
      issuerKey: intermediateKey,
      subjectName: 'MDS RSA Signer',
      issuerName: 'MDS Intermediate',
      serial: 4,
      keyUsage: 0x80,
      extendedKeyUsages: const <String>['1.3.6.1.5.5.7.3.3'],
    );
  });

  group('FIDO MDS JWS and PKIX verifier', () {
    test(
      'accepts spec-shaped ES256 and checks every non-anchor cert',
      () async {
        final checks = <FidoMetadataCertificateRevocationInput>[];
        final trust = _trust(root, (input) {
          checks.add(input);
          return FidoMetadataCertificateRevocationStatus.good;
        });
        final blob = await _loadVerified(
          compact: _compactEs256(
            key: leafKey,
            certificates: <List<int>>[leaf, intermediate],
            now: now,
          ),
          trust: trust,
          now: now,
        );

        expect(blob.number, 2);
        expect(checks, hasLength(2));
        expect(checks.first.certificate.serialNumber, BigInt.from(3));
        expect(checks.last.certificate.serialNumber, BigInt.from(2));
        expect(checks.first.issuer.serialNumber, BigInt.from(2));
        expect(checks.last.issuer.serialNumber, BigInt.one);
        expect(checks.first.certificate.extendedKeyUsages, <String>[
          '1.3.6.1.5.5.7.3.1',
          '1.3.6.1.5.5.7.3.2',
        ]);
        expect(
          () => checks.first.certificate.derBytes[0] = 0,
          throwsUnsupportedError,
        );
      },
    );

    test('accepts RS256 JWS with an RSA leaf key', () async {
      final blob = await _loadVerified(
        compact: _compactRs256(
          key: rsaLeafKey,
          certificates: <List<int>>[rsaLeaf, intermediate],
          now: now,
        ),
        trust: _goodTrust(root),
        now: now,
      );

      expect(blob.algorithm, 'RS256');
    });

    test('rejects DER where ES256 requires raw JWS r and s', () async {
      final compact = _compactEs256(
        key: leafKey,
        certificates: <List<int>>[leaf, intermediate],
        now: now,
        useDerJwsSignature: true,
      );

      await expectLater(
        _loadVerified(compact: compact, trust: _goodTrust(root), now: now),
        throwsA(isA<FidoMetadataException>()),
      );
    });

    test(
      'rejects malformed certificates and tampered JWS without details',
      () async {
        final truncated = leaf.sublist(0, leaf.length - 1);
        final tampered = _compactEs256(
          key: leafKey,
          certificates: <List<int>>[leaf, intermediate],
          now: now,
        );
        final segments = tampered.split('.');
        final signature = base64Url.decode(base64Url.normalize(segments.last));
        signature[0] ^= 0x01;
        final badSignature =
            '${segments[0]}.${segments[1]}.${_base64Url(signature)}';

        for (final compact in <String>[
          _compactEs256(
            key: leafKey,
            certificates: <List<int>>[truncated, intermediate],
            now: now,
          ),
          badSignature,
        ]) {
          await expectLater(
            _loadVerified(compact: compact, trust: _goodTrust(root), now: now),
            throwsA(
              isA<FidoMetadataException>().having(
                (error) => error.toString(),
                'safe message',
                'FidoMetadataException(invalid metadata)',
              ),
            ),
          );
        }
      },
    );

    test(
      'rejects invalid leaf usage and unsupported critical extensions',
      () async {
        final fixtures = <Uint8List>[
          _certificate(
            subjectKey: leafKey,
            issuerKey: intermediateKey,
            subjectName: 'Wrong EKU',
            issuerName: 'MDS Intermediate',
            serial: 10,
            keyUsage: 0x80,
            extendedKeyUsages: const <String>['1.3.6.1.5.5.7.3.4'],
          ),
          _certificate(
            subjectKey: leafKey,
            issuerKey: intermediateKey,
            subjectName: 'Wrong key usage',
            issuerName: 'MDS Intermediate',
            serial: 11,
            keyUsage: 0x20,
          ),
          _certificate(
            subjectKey: leafKey,
            issuerKey: intermediateKey,
            subjectName: 'Unknown critical extension',
            issuerName: 'MDS Intermediate',
            serial: 12,
            keyUsage: 0x80,
            unsupportedCriticalExtension: true,
          ),
        ];

        for (final invalidLeaf in fixtures) {
          await expectLater(
            _loadVerified(
              compact: _compactEs256(
                key: leafKey,
                certificates: <List<int>>[invalidLeaf, intermediate],
                now: now,
              ),
              trust: _goodTrust(root),
              now: now,
            ),
            throwsA(isA<FidoMetadataException>()),
          );
        }
      },
    );

    test(
      'rejects invalid names, signatures, CA constraints, and path length',
      () async {
        final wrongName = _certificate(
          subjectKey: leafKey,
          issuerKey: intermediateKey,
          subjectName: 'Wrong name leaf',
          issuerName: 'Not the intermediate',
          serial: 20,
          keyUsage: 0x80,
        );
        final wrongSignature = _certificate(
          subjectKey: leafKey,
          issuerKey: leafKey,
          subjectName: 'Wrong signature leaf',
          issuerName: 'MDS Intermediate',
          serial: 21,
          keyUsage: 0x80,
        );
        final notCaIntermediate = _certificate(
          subjectKey: intermediateKey,
          issuerKey: rootKey,
          subjectName: 'MDS Intermediate',
          issuerName: 'MDS Root',
          serial: 22,
          keyUsage: 0x06,
        );
        final pathLengthZeroRoot = _certificate(
          subjectKey: rootKey,
          issuerKey: rootKey,
          subjectName: 'MDS Root',
          issuerName: 'MDS Root',
          serial: 23,
          isCertificateAuthority: true,
          keyUsage: 0x06,
          pathLength: 0,
        );
        final invalidCases = <(Uint8List, Uint8List)>[
          (wrongName, root),
          (wrongSignature, root),
          (leaf, pathLengthZeroRoot),
        ];
        for (final fixture in invalidCases) {
          await expectLater(
            _loadVerified(
              compact: _compactEs256(
                key: leafKey,
                certificates: <List<int>>[fixture.$1, intermediate],
                now: now,
              ),
              trust: _goodTrust(fixture.$2),
              now: now,
            ),
            throwsA(isA<FidoMetadataException>()),
          );
        }
        await expectLater(
          _loadVerified(
            compact: _compactEs256(
              key: leafKey,
              certificates: <List<int>>[leaf, notCaIntermediate],
              now: now,
            ),
            trust: _goodTrust(root),
            now: now,
          ),
          throwsA(isA<FidoMetadataException>()),
        );
      },
    );

    test(
      'rejects expired paths and anchors other than the exact pin',
      () async {
        final expiredLeaf = _certificate(
          subjectKey: leafKey,
          issuerKey: intermediateKey,
          subjectName: 'Expired signer',
          issuerName: 'MDS Intermediate',
          serial: 30,
          keyUsage: 0x80,
          notAfter: DateTime.utc(2029, 1, 1),
        );
        final differentRootKey = _EcKey.create(BigInt.from(9));
        final differentRoot = _certificate(
          subjectKey: differentRootKey,
          issuerKey: differentRootKey,
          subjectName: 'MDS Root',
          issuerName: 'MDS Root',
          serial: 31,
          isCertificateAuthority: true,
          keyUsage: 0x06,
        );
        for (final fixture in <(Uint8List, Uint8List)>[
          (expiredLeaf, root),
          (leaf, differentRoot),
        ]) {
          await expectLater(
            _loadVerified(
              compact: _compactEs256(
                key: leafKey,
                certificates: <List<int>>[fixture.$1, intermediate],
                now: now,
              ),
              trust: _goodTrust(fixture.$2),
              now: now,
            ),
            throwsA(isA<FidoMetadataException>()),
          );
        }
      },
    );

    test(
      'fails closed for revoked, unknown, and throwing status checks',
      () async {
        for (final checker in <FidoMetadataCertificateRevocationChecker>[
          (_) => FidoMetadataCertificateRevocationStatus.revoked,
          (_) => FidoMetadataCertificateRevocationStatus.unknown,
          (_) => throw StateError('private revocation backend details'),
        ]) {
          await expectLater(
            _loadVerified(
              compact: _compactEs256(
                key: leafKey,
                certificates: <List<int>>[leaf, intermediate],
                now: now,
              ),
              trust: _trust(root, checker),
              now: now,
            ),
            throwsA(
              isA<FidoMetadataException>().having(
                (error) => error.toString(),
                'safe message',
                'FidoMetadataException(invalid metadata)',
              ),
            ),
          );
        }
      },
    );

    test('copies trust anchors before verification', () async {
      final mutableRoot = List<int>.from(root);
      final trust = _goodTrust(mutableRoot);
      mutableRoot[0] = 0;

      expect(trust.trustAnchors.single, root);
      expect(() => trust.trustAnchors.single[0] = 0, throwsUnsupportedError);
      expect(
        (await _loadVerified(
          compact: _compactEs256(
            key: leafKey,
            certificates: <List<int>>[leaf, intermediate],
            now: now,
          ),
          trust: trust,
          now: now,
        )).number,
        2,
      );
    });
  });

  group('FIDO MDS downloader', () {
    test('requires HTTPS and same-origin bounded redirects', () async {
      expect(
        () => FidoMetadataDownloader(
          trust: _goodTrust(root),
          source: Uri.parse('http://user:secret@metadata.example/blob'),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'redacted source',
            isNot(contains('secret')),
          ),
        ),
      );
      final crossOrigin = _QueueTransport(<_TransportStep>[
        (_) => FidoMetadataHttpResponse(
          statusCode: 302,
          bodyBytes: const <int>[],
          headers: const <String, String>{
            'location': 'https://attacker.example/blob',
          },
        ),
      ]);
      final downloader = _downloader(
        root: root,
        transport: crossOrigin,
        now: now,
      );
      addTearDown(downloader.close);

      await expectLater(
        downloader.refresh(),
        throwsA(isA<FidoMetadataException>()),
      );
      expect(crossOrigin.requests, hasLength(1));
    });

    test(
      'follows same-origin redirects and enforces the redirect count',
      () async {
        final compact = _compactEs256(
          key: leafKey,
          certificates: <List<int>>[leaf, intermediate],
          now: now,
        );
        final transport = _QueueTransport(<_TransportStep>[
          (_) => FidoMetadataHttpResponse(
            statusCode: 307,
            bodyBytes: const <int>[],
            headers: const <String, String>{'location': '/next'},
          ),
          (_) => FidoMetadataHttpResponse(
            statusCode: 200,
            bodyBytes: utf8.encode(compact),
            headers: const <String, String>{'content-type': 'application/jwt'},
          ),
        ]);
        final downloader = _downloader(
          root: root,
          transport: transport,
          now: now,
          policy: const FidoMetadataDownloadPolicy(maxRedirects: 1),
        );
        addTearDown(downloader.close);

        expect((await downloader.refresh()).blob.number, 2);
        expect(transport.requests.last.uri.path, '/next');

        final looping = _QueueTransport(<_TransportStep>[
          for (var i = 0; i < 2; i++)
            (_) => FidoMetadataHttpResponse(
              statusCode: 302,
              bodyBytes: const <int>[],
              headers: const <String, String>{'location': '/again'},
            ),
        ]);
        final bounded = _downloader(
          root: root,
          transport: looping,
          now: now,
          policy: const FidoMetadataDownloadPolicy(maxRedirects: 1),
        );
        addTearDown(bounded.close);
        await expectLater(
          bounded.refresh(),
          throwsA(isA<FidoMetadataException>()),
        );
      },
    );

    test(
      'enforces body, header, content-length, and total timeout bounds',
      () async {
        final responses = <_TransportStep>[
          (_) => FidoMetadataHttpResponse(
            statusCode: 200,
            bodyBytes: List<int>.filled(1025, 0x61),
          ),
          (_) => FidoMetadataHttpResponse(
            statusCode: 200,
            bodyBytes: const <int>[1],
            headers: <String, String>{'x-large': 'a' * 300},
          ),
          (_) => FidoMetadataHttpResponse(
            statusCode: 200,
            bodyBytes: const <int>[1],
            headers: const <String, String>{'content-length': '2'},
          ),
          (_) => FidoMetadataHttpResponse(
            statusCode: 200,
            bodyBytes: const <int>[1],
            headers: const <String, String>{'x-test': 'ok\r\nbad'},
          ),
          (_) => FidoMetadataHttpResponse(
            statusCode: 200,
            bodyBytes: const <int>[1],
            headers: const <String, String>{'ETag': 'one', 'etag': 'two'},
          ),
          (_) => FidoMetadataHttpResponse(
            statusCode: 200,
            bodyBytes: const <int>[256],
          ),
          (_) => Completer<FidoMetadataHttpResponse>().future,
        ];
        for (final response in responses) {
          final transport = _QueueTransport(<_TransportStep>[response]);
          final downloader = _downloader(
            root: root,
            transport: transport,
            now: now,
            policy: const FidoMetadataDownloadPolicy(
              perRequestTimeout: Duration(milliseconds: 10),
              totalRefreshTimeout: Duration(milliseconds: 100),
              maxResponseBytes: 1024,
              maxResponseHeaderBytes: 256,
            ),
          );
          addTearDown(downloader.close);
          await expectLater(
            downloader.refresh(),
            throwsA(isA<FidoMetadataException>()),
          );
        }
      },
    );

    test('sends validators and safely reuses only a fresh 304 cache', () async {
      final compact = _compactEs256(
        key: leafKey,
        certificates: <List<int>>[leaf, intermediate],
        now: now,
      );
      final firstTransport = _QueueTransport(<_TransportStep>[
        (_) => FidoMetadataHttpResponse(
          statusCode: 200,
          bodyBytes: utf8.encode(compact),
          headers: const <String, String>{
            'content-type': 'application/jwt',
            'etag': '"blob-2"',
          },
        ),
      ]);
      final firstDownloader = _downloader(
        root: root,
        transport: firstTransport,
        now: now,
      );
      addTearDown(firstDownloader.close);
      final first = await firstDownloader.refresh();

      final notModified = _QueueTransport(<_TransportStep>[
        (_) => FidoMetadataHttpResponse(
          statusCode: 304,
          bodyBytes: const <int>[],
          headers: const <String, String>{'etag': '"blob-2"'},
        ),
      ]);
      final secondDownloader = _downloader(
        root: root,
        transport: notModified,
        now: now.add(const Duration(hours: 1)),
      );
      addTearDown(secondDownloader.close);
      final second = await secondDownloader.refresh(previous: first);

      expect(second.wasDownloaded, isFalse);
      expect(second.blob, same(first.blob));
      expect(second.etag, '"blob-2"');
      expect(notModified.requests.single.headers['if-none-match'], '"blob-2"');
      expect(
        notModified.requests.single.uri.queryParameters['localCopySerial'],
        '2',
      );
    });

    test(
      'rejects unconditioned, mismatched, stale, and clock-rollback 304s',
      () async {
        final compact = _compactEs256(
          key: leafKey,
          certificates: <List<int>>[leaf, intermediate],
          now: now,
        );
        final cases = <({DateTime clock, String? etag, String? responseEtag})>[
          (clock: now, etag: null, responseEtag: null),
          (clock: now, etag: '"old"', responseEtag: '"different"'),
          (
            clock: now.add(const Duration(days: 46)),
            etag: '"old"',
            responseEtag: '"old"',
          ),
          (
            clock: now.subtract(const Duration(hours: 1)),
            etag: '"old"',
            responseEtag: '"old"',
          ),
        ];
        for (final fixture in cases) {
          final previous = await _downloadResult(
            root: root,
            compact: compact,
            etag: fixture.etag,
            now: now,
          );
          final transport = _QueueTransport(<_TransportStep>[
            (_) => FidoMetadataHttpResponse(
              statusCode: 304,
              bodyBytes: const <int>[],
              headers: <String, String>{'etag': ?fixture.responseEtag},
            ),
          ]);
          final downloader = _downloader(
            root: root,
            transport: transport,
            now: fixture.clock,
          );
          addTearDown(downloader.close);
          await expectLater(
            downloader.refresh(previous: previous),
            throwsA(isA<FidoMetadataException>()),
          );
        }
      },
    );

    test('rejects non-increasing downloaded blob numbers', () async {
      final previous = await _downloadResult(
        root: root,
        compact: _compactEs256(
          key: leafKey,
          certificates: <List<int>>[leaf, intermediate],
          now: now,
        ),
        now: now,
      );
      for (final number in <int>[1, 2]) {
        final transport = _QueueTransport(<_TransportStep>[
          (_) => FidoMetadataHttpResponse(
            statusCode: 200,
            bodyBytes: utf8.encode(
              _compactEs256(
                key: leafKey,
                certificates: <List<int>>[leaf, intermediate],
                now: now,
                number: number,
              ),
            ),
            headers: const <String, String>{'content-type': 'application/jwt'},
          ),
        ]);
        final downloader = _downloader(
          root: root,
          transport: transport,
          now: now,
        );
        addTearDown(downloader.close);
        await expectLater(
          downloader.refresh(previous: previous),
          throwsA(isA<FidoMetadataException>()),
        );
      }
    });

    test('one per-hop deadline covers delayed headers and full body', () async {
      final compact = _compactEs256(
        key: leafKey,
        certificates: <List<int>>[leaf, intermediate],
        now: now,
      );
      final client = _DelayedClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        final controller = StreamController<List<int>>();
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 25), () {
            controller
              ..add(utf8.encode(compact))
              ..close();
          }),
        );
        return http.StreamedResponse(
          controller.stream,
          200,
          headers: const <String, String>{'content-type': 'application/jwt'},
        );
      });
      final downloader = FidoMetadataDownloader(
        trust: _goodTrust(root),
        httpTransport: FidoMetadataHttpTransport.packageHttp(client: client),
        clock: () => now,
        source: Uri.parse('https://metadata.example/blob'),
        policy: const FidoMetadataDownloadPolicy(
          perRequestTimeout: Duration(milliseconds: 40),
          totalRefreshTimeout: Duration(seconds: 1),
        ),
      );

      await expectLater(
        downloader.refresh(),
        throwsA(isA<FidoMetadataException>()),
      );
      expect(client.requests, 1);
    });

    test('one total deadline spans redirects and verification work', () async {
      final compact = _compactEs256(
        key: leafKey,
        certificates: <List<int>>[leaf, intermediate],
        now: now,
      );
      final transport = _QueueTransport(<_TransportStep>[
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return FidoMetadataHttpResponse(
            statusCode: 307,
            bodyBytes: const <int>[],
            headers: const <String, String>{'location': '/second'},
          );
        },
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return FidoMetadataHttpResponse(
            statusCode: 307,
            bodyBytes: const <int>[],
            headers: const <String, String>{'location': '/final'},
          );
        },
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return FidoMetadataHttpResponse(
            statusCode: 200,
            bodyBytes: utf8.encode(compact),
            headers: const <String, String>{'content-type': 'application/jwt'},
          );
        },
      ]);
      final downloader = FidoMetadataDownloader(
        trust: _goodTrust(root),
        httpTransport: transport,
        clock: () => now,
        source: Uri.parse('https://metadata.example/blob'),
        policy: const FidoMetadataDownloadPolicy(
          perRequestTimeout: Duration(milliseconds: 100),
          totalRefreshTimeout: Duration(milliseconds: 50),
        ),
      );

      await expectLater(
        downloader.refresh(),
        throwsA(isA<FidoMetadataException>()),
      );
      expect(transport.requests, hasLength(3));

      final verificationTransport = _QueueTransport(<_TransportStep>[
        (_) => FidoMetadataHttpResponse(
          statusCode: 200,
          bodyBytes: utf8.encode(compact),
          headers: const <String, String>{'content-type': 'application/jwt'},
        ),
      ]);
      final verificationDownloader = FidoMetadataDownloader(
        trust: _trust(root, (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return FidoMetadataCertificateRevocationStatus.good;
        }),
        httpTransport: verificationTransport,
        clock: () => now,
        source: Uri.parse('https://metadata.example/blob'),
        policy: const FidoMetadataDownloadPolicy(
          perRequestTimeout: Duration(milliseconds: 100),
          totalRefreshTimeout: Duration(milliseconds: 50),
        ),
      );
      await expectLater(
        verificationDownloader.refresh(),
        throwsA(isA<FidoMetadataException>()),
      );
    });

    test(
      'rejects cache state from a different source or trust domain',
      () async {
        final previous = await _downloadResult(
          root: root,
          compact: _compactEs256(
            key: leafKey,
            certificates: <List<int>>[leaf, intermediate],
            now: now,
          ),
          now: now,
          etag: '"blob-2"',
        );
        final transport = _QueueTransport(const <_TransportStep>[]);
        final downloader = FidoMetadataDownloader(
          trust: _goodTrust(root),
          httpTransport: transport,
          clock: () => now,
          source: Uri.parse('https://other.example/blob'),
        );

        await expectLater(
          downloader.refresh(previous: previous),
          throwsA(isA<FidoMetadataException>()),
        );
        expect(transport.requests, isEmpty);
      },
    );
  });
}

typedef _TransportStep =
    FutureOr<FidoMetadataHttpResponse> Function(
      FidoMetadataHttpRequest request,
    );

final class _QueueTransport implements FidoMetadataHttpTransport {
  _QueueTransport(this._steps);

  final List<_TransportStep> _steps;
  final List<FidoMetadataHttpRequest> requests = <FidoMetadataHttpRequest>[];
  var closed = false;

  @override
  Future<FidoMetadataHttpResponse> get(FidoMetadataHttpRequest request) async {
    requests.add(request);
    if (_steps.isEmpty) throw StateError('No queued response');
    return await _steps.removeAt(0)(request);
  }

  @override
  void close() => closed = true;
}

final class _DelayedClient extends http.BaseClient {
  _DelayedClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;
  var requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    return _send(request);
  }
}

FidoMetadataDownloader _downloader({
  required List<int> root,
  required _QueueTransport transport,
  required DateTime now,
  FidoMetadataDownloadPolicy policy = const FidoMetadataDownloadPolicy(),
}) => FidoMetadataDownloader(
  trust: _goodTrust(root),
  httpTransport: transport,
  clock: () => now,
  source: Uri.parse('https://metadata.example/blob'),
  policy: policy,
);

Future<FidoMetadataRefreshResult> _downloadResult({
  required List<int> root,
  required String compact,
  required DateTime now,
  String? etag,
}) async {
  final transport = _QueueTransport(<_TransportStep>[
    (_) => FidoMetadataHttpResponse(
      statusCode: 200,
      bodyBytes: utf8.encode(compact),
      headers: <String, String>{
        'content-type': 'application/jwt',
        'etag': ?etag,
      },
    ),
  ]);
  final downloader = _downloader(root: root, transport: transport, now: now);
  return downloader.refresh();
}

FidoMetadataPkixTrust _goodTrust(List<int> root) =>
    _trust(root, (_) => FidoMetadataCertificateRevocationStatus.good);

FidoMetadataPkixTrust _trust(
  List<int> root,
  FidoMetadataCertificateRevocationChecker checker,
) => FidoMetadataPkixTrust(
  trustAnchors: <List<int>>[root],
  checkRevocation: checker,
);

Future<FidoMetadataBlob> _loadVerified({
  required String compact,
  required FidoMetadataPkixTrust trust,
  required DateTime now,
}) => FidoMetadataBlobLoader(
  trustAnchors: trust.trustAnchors,
  verifyJws: FidoMetadataJwsPkixVerifier(trust: trust).verify,
  nextUpdatePolicy: FidoMetadataNextUpdatePolicy.requireFreshWhenPresent,
).load(compact, now: now);

String _compactEs256({
  required _EcKey key,
  required List<List<int>> certificates,
  required DateTime now,
  int number = 2,
  bool useDerJwsSignature = false,
}) => _compact(
  algorithm: 'ES256',
  certificates: certificates,
  now: now,
  number: number,
  sign: (input) {
    final der = _signEs256Der(key, input);
    return useDerJwsSignature ? der : _rawEs256(der);
  },
);

String _compactRs256({
  required _RsaKey key,
  required List<List<int>> certificates,
  required DateTime now,
  int number = 2,
}) => _compact(
  algorithm: 'RS256',
  certificates: certificates,
  now: now,
  number: number,
  sign: (input) => _signRs256(key, input),
);

String _compact({
  required String algorithm,
  required List<List<int>> certificates,
  required DateTime now,
  required int number,
  required List<int> Function(List<int>) sign,
}) {
  final header = _base64UrlJson(<String, Object?>{
    'alg': algorithm,
    'typ': 'JWT',
    'x5c': certificates.map(base64.encode).toList(growable: false),
  });
  final payload = _base64UrlJson(<String, Object?>{
    'legalHeader':
        'https://fidoalliance.org/metadata/metadata-statement-legal-header/',
    'no': number,
    'nextUpdate': now.add(const Duration(days: 1)).toIso8601String(),
    'entries': const <Object?>[],
  });
  final signingInput = '$header.$payload';
  return '$signingInput.${_base64Url(sign(utf8.encode(signingInput)))}';
}

String _base64UrlJson(Object value) =>
    _base64Url(utf8.encode(jsonEncode(value)));

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

sealed class _CertificateKey {
  const _CertificateKey();

  ASN1Sequence subjectPublicKeyInfo();
}

final class _EcKey extends _CertificateKey {
  _EcKey._(this.privateKey, this.x, this.y);

  factory _EcKey.create(BigInt value) {
    final parameters = ECDomainParameters('secp256r1');
    final point = (parameters.G * value)!;
    return _EcKey._(
      ECPrivateKey(value, parameters),
      _bigIntBytes(point.x!.toBigInteger()!, 32),
      _bigIntBytes(point.y!.toBigInteger()!, 32),
    );
  }

  final ECPrivateKey privateKey;
  final Uint8List x;
  final Uint8List y;

  @override
  ASN1Sequence subjectPublicKeyInfo() => ASN1Sequence()
    ..add(
      ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.2.1'))
        ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.3.1.7')),
    )
    ..add(ASN1BitString(stringValues: <int>[0x04, ...x, ...y]));
}

final class _RsaKey extends _CertificateKey {
  _RsaKey._(this.privateKey, this.publicKey);

  factory _RsaKey.create() {
    final random = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(List<int>.generate(32, (index) => index + 19)),
        ),
      );
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    return _RsaKey._(pair.privateKey, pair.publicKey);
  }

  final RSAPrivateKey privateKey;
  final RSAPublicKey publicKey;

  @override
  ASN1Sequence subjectPublicKeyInfo() => ASN1Sequence()
    ..add(
      ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'))
        ..add(ASN1Null()),
    )
    ..add(
      ASN1BitString(
        stringValues:
            (ASN1Sequence()
                  ..add(ASN1Integer(publicKey.modulus!))
                  ..add(ASN1Integer(publicKey.publicExponent!)))
                .encode(),
      ),
    );
}

Uint8List _certificate({
  required _CertificateKey subjectKey,
  required _EcKey issuerKey,
  required String subjectName,
  required String issuerName,
  required int serial,
  bool isCertificateAuthority = false,
  bool basicConstraintsCritical = true,
  int? pathLength,
  int? keyUsage,
  List<String> extendedKeyUsages = const <String>[],
  bool unsupportedCriticalExtension = false,
  DateTime? notBefore,
  DateTime? notAfter,
}) {
  final signatureAlgorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromIdentifierString('1.2.840.10045.4.3.2'));
  final basicConstraints = ASN1Sequence();
  if (isCertificateAuthority) basicConstraints.add(ASN1Boolean(true));
  if (pathLength != null) {
    basicConstraints.add(ASN1Integer(BigInt.from(pathLength)));
  }
  final extensions = ASN1Sequence()
    ..add(
      _extension(
        '2.5.29.19',
        basicConstraints.encode(),
        critical: basicConstraintsCritical,
      ),
    );
  if (keyUsage != null) {
    extensions.add(
      _extension(
        '2.5.29.15',
        ASN1BitString(stringValues: <int>[keyUsage]).encode(),
        critical: true,
      ),
    );
  }
  if (extendedKeyUsages.isNotEmpty) {
    final usages = ASN1Sequence();
    for (final identifier in extendedKeyUsages) {
      usages.add(ASN1ObjectIdentifier.fromIdentifierString(identifier));
    }
    extensions.add(_extension('2.5.29.37', usages.encode()));
  }
  if (unsupportedCriticalExtension) {
    extensions.add(
      _extension('1.3.6.1.4.1.55555.1', ASN1Null().encode(), critical: true),
    );
  }
  final tbs = ASN1Sequence()
    ..add(_explicit(0xa0, ASN1Integer(BigInt.two).encode()))
    ..add(ASN1Integer(BigInt.from(serial)))
    ..add(signatureAlgorithm)
    ..add(_name(issuerName))
    ..add(
      ASN1Sequence()
        ..add(ASN1UtcTime(notBefore ?? DateTime.utc(2029, 1, 1)))
        ..add(ASN1UtcTime(notAfter ?? DateTime.utc(2031, 1, 1))),
    )
    ..add(_name(subjectName))
    ..add(subjectKey.subjectPublicKeyInfo())
    ..add(_explicit(0xa3, extensions.encode()));
  final signature = _signEs256Der(issuerKey, tbs.encode());
  return Uint8List.fromList(
    (ASN1Sequence()
          ..add(tbs)
          ..add(signatureAlgorithm)
          ..add(ASN1BitString(stringValues: signature)))
        .encode(),
  );
}

ASN1Sequence _extension(
  String identifier,
  List<int> value, {
  bool critical = false,
}) => ASN1Sequence()
  ..add(ASN1ObjectIdentifier.fromIdentifierString(identifier))
  ..addIf(critical, ASN1Boolean(true))
  ..add(ASN1OctetString(octets: Uint8List.fromList(value)));

extension on ASN1Sequence {
  void addIf(bool condition, ASN1Object value) {
    if (condition) add(value);
  }
}

ASN1Sequence _name(String commonName) => ASN1Sequence()
  ..add(
    ASN1Set()..add(
      ASN1Sequence()
        ..add(ASN1ObjectIdentifier.fromIdentifierString('2.5.4.3'))
        ..add(ASN1UTF8String(utf8StringValue: commonName)),
    ),
  );

ASN1Object _explicit(int tag, Uint8List value) {
  final object = ASN1Object(tag: tag)
    ..valueBytes = value
    ..valueByteLength = value.length;
  return object;
}

Uint8List _signEs256Der(_EcKey key, List<int> message) {
  final random = FortunaRandom()
    ..seed(
      KeyParameter(Uint8List.fromList(List<int>.generate(32, (i) => i + 1))),
    );
  final signer = ECDSASigner(SHA256Digest())
    ..init(
      true,
      ParametersWithRandom(
        PrivateKeyParameter<ECPrivateKey>(key.privateKey),
        random,
      ),
    );
  final signature = signer.generateSignature(Uint8List.fromList(message));
  if (signature is! ECSignature) throw StateError('Expected ECDSA signature');
  return Uint8List.fromList(
    (ASN1Sequence()
          ..add(ASN1Integer(signature.r))
          ..add(ASN1Integer(signature.s)))
        .encode(),
  );
}

Uint8List _rawEs256(Uint8List der) {
  final sequence = ASN1Parser(der).nextObject() as ASN1Sequence;
  final r = (sequence.elements![0] as ASN1Integer).integer!;
  final s = (sequence.elements![1] as ASN1Integer).integer!;
  return Uint8List.fromList(<int>[
    ..._bigIntBytes(r, 32),
    ..._bigIntBytes(s, 32),
  ]);
}

Uint8List _signRs256(_RsaKey key, List<int> message) {
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(key.privateKey));
  final signature = signer.generateSignature(Uint8List.fromList(message));
  return Uint8List.fromList(signature.bytes);
}

Uint8List _bigIntBytes(BigInt value, int length) {
  final result = Uint8List(length);
  var remaining = value;
  for (var index = length - 1; index >= 0; index--) {
    result[index] = (remaining & BigInt.from(0xff)).toInt();
    remaining >>= 8;
  }
  return result;
}
