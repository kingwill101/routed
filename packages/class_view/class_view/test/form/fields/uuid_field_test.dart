import 'package:class_view/class_view.dart';
import 'package:test/test.dart';

void main() {
  group('UUIDField Tests', () {
    test('validates valid UUID with dashes', () async {
      final field = UUIDField<String>();
      final value = field.toDart('550e8400-e29b-4123-a716-446655440000');
      expect(value, equals('550e8400-e29b-4123-a716-446655440000'));
    });

    test('handles null and empty values when not required', () async {
      final field = UUIDField<String>(required: false);
      expect(field.toDart(''), isNull);
      expect(field.toDart(null), isNull);
    });

    test('throws validation error for UUID without dashes', () async {
      final field = UUIDField<String>();
      expect(
        () => field.toDart('550e8400e29b41d4a716446655440000'),
        throwsA(
          predicate(
            (e) =>
                e is ValidationError &&
                e.toString().contains('Enter a valid UUID'),
          ),
        ),
      );
    });

    test('validates UUID version (1-5)', () async {
      final field = UUIDField<String>();

      // Test valid versions
      for (var version = 1; version <= 5; version++) {
        final uuid = '550e8400-e29b-${version}123-89ab-446655440000';
        final value = field.toDart(uuid);
        expect(value, equals(uuid));
      }

      // Test invalid version
      expect(
        () => field.toDart('550e8400-e29b-6123-89ab-446655440000'),
        throwsA(
          predicate(
            (e) =>
                e is ValidationError &&
                e.toString().contains('Enter a valid UUID'),
          ),
        ),
      );
    });

    test('validates UUID variant (8-b)', () async {
      final field = UUIDField<String>();

      // Test valid variants (8, 9, a, b)
      final variants = ['8', '9', 'a', 'b'];
      for (var variant in variants) {
        final uuid = '550e8400-e29b-4123-${variant}9ab-446655440000';
        final value = field.toDart(uuid);
        expect(value, equals(uuid));
      }

      // Test invalid variant
      expect(
        () => field.toDart('550e8400-e29b-4123-c9ab-446655440000'),
        throwsA(
          predicate(
            (e) =>
                e is ValidationError &&
                e.toString().contains('Enter a valid UUID'),
          ),
        ),
      );
    });
  });
}
