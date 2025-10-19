import 'package:routed/routed.dart';
import 'package:test/test.dart';

void main() {
  group('ContentNegotiator', () {
    test('selects highest quality and specificity', () {
      final result = ContentNegotiator.negotiate(
        'application/xml, application/json;q=0.8',
        const ['application/json', 'application/xml'],
      );

      expect(result, isNotNull);
      expect(result!.value, equals('application/xml'));
      expect(result.quality, closeTo(1.0, 0.00001));
    });

    test('respects wildcard with fallback', () {
      final result = ContentNegotiator.negotiate('*/*;q=0.2', const [
        'application/json',
        'text/plain',
      ], defaultType: 'text/plain');

      expect(result, isNotNull);
      expect(result!.value, equals('application/json'));
    });

    test('falls back to provided default when header missing', () {
      final result = ContentNegotiator.negotiate(null, const [
        'application/json',
        'application/xml',
      ], defaultType: 'application/xml');

      expect(result, isNotNull);
      expect(result!.value, equals('application/xml'));
    });

    test('falls back to first supported when no match and no default', () {
      final result = ContentNegotiator.negotiate('text/plain', const [
        'application/json',
      ]);

      expect(result, isNotNull);
      expect(result!.value, equals('application/json'));
    });
  });
}
