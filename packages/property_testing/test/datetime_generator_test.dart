import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';

void main() {
  group('DateTime Generator', () {
    test('generates dates within specified range', () async {
      final min = DateTime(2000);
      final max = DateTime(2024);

      final runner = PropertyTestRunner(
        Specialized.dateTime(min: min, max: max),
        (date) {
          expect(date.isBefore(min), isFalse);
          expect(date.isAfter(max), isFalse);
        },
        PropertyConfig(numTests: 1000),
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('respects UTC flag', () async {
      final runner = PropertyTestRunner(
        Specialized.dateTime(utc: true),
        (date) {
          expect(date.isUtc, isTrue);
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates non-UTC dates when UTC is false', () async {
      final runner = PropertyTestRunner(
        Specialized.dateTime(utc: false),
        (date) {
          expect(date.isUtc, isFalse);
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('shrinks towards epoch while respecting minimum', () async {
      final min = DateTime(2020);

      final runner = PropertyTestRunner(
        Specialized.dateTime(min: min),
        (date) {
          fail('Triggering shrink');
        },
      );

      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.failingInput, isNotNull);
      expect((result.failingInput as DateTime).isBefore(min), isFalse,
          reason: 'Shrunk value should not be before min');
      expect((result.failingInput as DateTime).isBefore(DateTime(2024)), isTrue,
          reason: 'Shrunk value should be before 2024');
    });

    test('generates dates across full range', () async {
      final min = DateTime(2000);
      final max = DateTime(2001);
      final seenMonths = <int, int>{};
      final seenDays = <int>{};
      final seenHours = <int>{};

      final runner = PropertyTestRunner(
        Specialized.dateTime(min: min, max: max),
        (date) {
          seenMonths[date.month] = (seenMonths[date.month] ?? 0) + 1;
          seenDays.add(date.day);
          seenHours.add(date.hour);
        },
        PropertyConfig(numTests: 1000),
      );

      await runner.run();

      expect(seenMonths.length, greaterThan(6)); // Should see most months
      expect(seenDays.length, greaterThan(15)); // Should see many days
      expect(seenHours.length, greaterThan(12)); // Should see many hours
    });

    test('handles dates near epoch', () async {
      final min = DateTime.fromMillisecondsSinceEpoch(0);
      final max = DateTime.fromMillisecondsSinceEpoch(86400000); // 1 day

      final runner = PropertyTestRunner(
        Specialized.dateTime(
          min: min,
          max: max,
          utc: true, // Force UTC to avoid timezone issues
        ),
        (date) {
          // Check that it's either Dec 31, 1969 or Jan 1, 1970 depending on timezone
          if (date.isUtc) {
            expect(date.year, equals(1970), reason: 'UTC year should be 1970');
            expect(date.month, equals(1), reason: 'UTC month should be 1');
            expect(date.day, anyOf(equals(1), equals(2)),
                reason: 'UTC day should be 1 or 2');
          } else {
            // In local time, might be Dec 31, 1969 in some timezones
            if (date.year == 1969) {
              expect(date.month, equals(12),
                  reason: 'Month should be 12 for 1969');
              expect(date.day, equals(31),
                  reason: 'Day should be 31 for Dec 1969');
            } else {
              expect(date.year, equals(1970), reason: 'Year should be 1970');
              expect(date.month, equals(1), reason: 'Month should be 1');
              expect(date.day, anyOf(equals(1), equals(2)),
                  reason: 'Day should be 1 or 2');
            }
          }
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('handles far future dates', () async {
      final farFuture = DateTime(9999);

      final runner = PropertyTestRunner(
        Specialized.dateTime(max: farFuture),
        (date) {
          expect(date.millisecondsSinceEpoch,
              lessThanOrEqualTo(farFuture.millisecondsSinceEpoch));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('preserves millisecond precision', () async {
      final seenMilliseconds = <int>{};

      final runner = PropertyTestRunner(
        Specialized.dateTime(),
        (date) {
          seenMilliseconds.add(date.millisecond);
        },
        PropertyConfig(numTests: 1000),
      );

      await runner.run();
      expect(seenMilliseconds.length,
          greaterThan(50)); // Should see many different milliseconds
    });

    test('handles leap year dates correctly', () async {
      final runner = PropertyTestRunner(
        Specialized.dateTime(
          min: DateTime(2020, 2, 28),
          max: DateTime(2020, 3, 1),
        ),
        (date) {
          if (date.month == 2 && date.day == 29) {
            expect(date.year, equals(2020)); // Must be leap year
          }
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('handles timezone transitions', () async {
      // Test around daylight savings transitions
      final runner = PropertyTestRunner(
        Specialized.dateTime(
          min: DateTime(2024, 3, 10), // US DST start
          max: DateTime(2024, 3, 11),
          utc: false,
        ),
        (date) {
          expect(date.isUtc, isFalse);
          // All generated times should be valid local times
          expect(() => date.toLocal(), returnsNormally);
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('maintains chronological order', () async {
      final dates = <DateTime>[];
      final min = DateTime(2000);
      final max = DateTime(2001);

      final runner = PropertyTestRunner(
        Specialized.dateTime(
          min: min,
          max: max,
        ),
        (date) {
          dates.add(date);
          if (dates.length >= 2) {
            for (var i = 1; i < dates.length; i++) {
              expect(dates[i - 1].isAfter(dates[i]), isFalse,
                  reason: 'Dates should be in chronological order');
            }
          }
        },
        PropertyConfig(numTests: 100),
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('handles microsecond precision consistently', () async {
      final runner = PropertyTestRunner(
        Specialized.dateTime(),
        (date) {
          final serialized = date.toIso8601String();
          final parsed = DateTime.parse(serialized);
          expect(parsed, equals(date));
          expect(parsed.microsecondsSinceEpoch,
              equals(date.microsecondsSinceEpoch));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });
  });
}
