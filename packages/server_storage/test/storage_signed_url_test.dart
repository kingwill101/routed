import 'package:server_storage/server_storage.dart';
import 'package:test/test.dart';

void main() {
  group('StorageSignedUrlSigner', () {
    final signer = StorageSignedUrlSigner(
      'test-storage-signing-key-with-at-least-32-bytes',
    );
    final now = DateTime.now().toUtc();

    test('accepts the exact URL until it expires', () {
      final signed = signer.sign(
        Uri.parse('https://files.example.test/private/report.pdf?download=1'),
        expiresAt: now.add(const Duration(minutes: 5)),
      );

      expect(signer.verify(signed, now: now), isTrue);
      expect(signer.verify(signed, method: 'HEAD', now: now), isTrue);
      expect(
        signer.verify(
          signed,
          now: now.add(const Duration(minutes: 5)),
        ),
        isFalse,
      );
    });

    test('rejects tampered paths, queries, and signatures', () {
      final signed = signer.sign(
        Uri.parse('https://files.example.test/private/report.pdf?download=1'),
        expiresAt: now.add(const Duration(minutes: 5)),
      );

      expect(
        signer.verify(signed.replace(path: '/private/other.pdf'), now: now),
        isFalse,
      );
      expect(
        signer.verify(
          signed.replace(
            queryParameters: {
              ...signed.queryParameters,
              'download': '0',
            },
          ),
          now: now,
        ),
        isFalse,
      );
      expect(
        signer.verify(
          signed.replace(
            queryParameters: {
              ...signed.queryParameters,
              'signature': 'invalid',
            },
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('rejects weak secrets and ambiguous reserved parameters', () {
      const weakSecret = 'sensitive-too-short-secret';
      expect(
        () => StorageSignedUrlSigner(weakSecret),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains(weakSecret)),
          ),
        ),
      );
      const capability = 'sensitive-capability-value';
      expect(
        () => signer.sign(
          Uri.parse(
            'https://files.example.test/file?expires=1&token=$capability',
          ),
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains(capability)),
          ),
        ),
      );
    });

    test('URL validation errors omit capability URLs', () {
      const capability = 'private-capability-token';
      final url = Uri.parse(
        'https://user:$capability@files.example.test/private/report.pdf',
      );

      expect(
        () => signer.sign(
          url,
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.toString(),
            'message',
            isNot(contains(capability)),
          ),
        ),
      );
    });
  });
}
