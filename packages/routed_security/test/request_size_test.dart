import 'package:routed_security/routed_security.dart';
import 'package:test/test.dart';

void main() {
  group('request size helpers', () {
    test('resolves content length from preferred sources', () {
      expect(
        resolveContentLength(
          headersContentLength: 10,
          requestContentLength: -1,
          rawContentLength: null,
        ),
        10,
      );
      expect(
        resolveContentLength(
          headersContentLength: -1,
          requestContentLength: 15,
          rawContentLength: null,
        ),
        15,
      );
      expect(
        resolveContentLength(
          headersContentLength: -1,
          requestContentLength: -1,
          rawContentLength: '20',
        ),
        20,
      );
    });

    test('detects when request exceeds limit', () {
      expect(
        exceedsRequestBodyLimit(
          maxBytes: 100,
          headersContentLength: 101,
          requestContentLength: -1,
          rawContentLength: null,
        ),
        isTrue,
      );
      expect(
        exceedsRequestBodyLimit(
          maxBytes: 100,
          headersContentLength: -1,
          requestContentLength: -1,
          rawContentLength: null,
        ),
        isFalse,
      );
    });
  });
}
