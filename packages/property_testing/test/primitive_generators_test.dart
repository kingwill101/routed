import 'dart:math' show Random;

import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';

void main() {
  group('Primitive Generators (Gen)', () {
    test('Gen.integer generates within range', () async {
      final min = -10;
      final max = 10;
      final gen = Gen.integer(min: min, max: max);
      final runner = PropertyTestRunner(gen, (value) {
        expect(value, greaterThanOrEqualTo(min));
        expect(value, lessThanOrEqualTo(max));
      }, PropertyConfig(numTests: 100));
      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('Gen.double_ generates within range', () async {
      final min = -5.5;
      final max = 5.5;
      final gen = Gen.double_(min: min, max: max);
      final runner = PropertyTestRunner(gen, (value) {
        expect(value, greaterThanOrEqualTo(min));
        expect(value, lessThanOrEqualTo(max));
      }, PropertyConfig(numTests: 100));
      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('Gen.boolean generates both true and false', () async {
      final gen = Gen.boolean();
      final values = <bool>{};
      final runner = PropertyTestRunner(gen, (value) {
        values.add(value);
      }, PropertyConfig(numTests: 50)); // Increase chance of seeing both
      await runner.run();
      expect(values, contains(true));
      expect(values, contains(false));
    });
    test('Gen.boolean shrinks true to false', () async {
      // Rather than trying to test through the PropertyTestRunner, let's test
      // the boolean generator's shrinking behavior directly
      final gen = Gen.boolean();

      // Generate a true value
      // We'll use a fixed seed to ensure we get true
      final shrinkableValue = gen.generate(Random(123));
      expect(
        shrinkableValue.value,
        isTrue,
        reason: 'Should generate true with this seed',
      );

      // Check that it produces shrinks
      final shrinks = shrinkableValue.shrinks().toList();
      expect(
        shrinks.isNotEmpty,
        isTrue,
        reason: 'Should produce at least one shrink',
      );

      // Verify that the shrink is false
      expect(
        shrinks.first.value,
        isFalse,
        reason: 'Should shrink true to false',
      );
    });

    test('Gen.boolean does not shrink false', () async {
      final runner = PropertyTestRunner(
        Gen.constant(false), // Start with false
        (value) => fail('Force shrink'),
        PropertyConfig(numTests: 1),
      );
      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.originalFailingInput, isFalse);
      expect(result.failingInput, isFalse); // Cannot shrink further
      expect(result.numShrinks, equals(0));
    });

    test('Gen.string generates strings within length constraints', () async {
      final minLength = 5;
      final maxLength = 15;
      final gen = Gen.string(minLength: minLength, maxLength: maxLength);
      final runner = PropertyTestRunner(gen, (value) {
        expect(value.length, greaterThanOrEqualTo(minLength));
        expect(value.length, lessThanOrEqualTo(maxLength));
        expect(value, matches(r'^[a-zA-Z0-9]*$')); // Default charset
      }, PropertyConfig(numTests: 100));
      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('Gen.oneOf selects from the provided list', () async {
      final options = [10, 20, 30, 40];
      final gen = Gen.oneOf(options);
      final seen = <int>{};
      final runner = PropertyTestRunner(gen, (value) {
        expect(options, contains(value));
        seen.add(value);
      }, PropertyConfig(numTests: 100));
      await runner.run();
      // Should see most, if not all, options
      expect(seen.length, greaterThanOrEqualTo(3));
    });

    test('Gen.constant always generates the same value', () async {
      final value = 99;
      final gen = Gen.constant(value);
      final runner = PropertyTestRunner(gen, (v) {
        expect(v, equals(value));
      }, PropertyConfig(numTests: 10));
      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('Gen.integer shrinks towards 0 or boundary', () async {
      final gen = Gen.integer(min: -50, max: 100);
      final runner = PropertyTestRunner(
        gen,
        (value) {
          if (value.abs() > 10) {
            // Fail on larger values
            fail('Value $value too far from zero');
          }
        },
        PropertyConfig(numTests: 50), // Ensure we hit a failing case
      );

      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.failingInput, isNotNull);
      expect(
        (result.failingInput as int).abs(),
        lessThanOrEqualTo((result.originalFailingInput as int).abs()),
      );
      // The minimal failing case should be just outside the passing range
      expect(
        (result.failingInput as int).abs(),
        closeTo(11, 1),
        reason: 'Should shrink close to the failure boundary',
      );
    });

    test('Gen.double_ shrinks towards 0 or boundary', () async {
      final gen = Gen.double_(min: -10.0, max: 20.0);
      final runner = PropertyTestRunner(
        gen,
        (value) {
          if (value.abs() > 1.0) {
            // Fail if magnitude > 1.0
            fail('Value $value too far from zero');
          }
        },
        PropertyConfig(numTests: 100), // Ensure hitting a failing case
      );

      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.failingInput, isNotNull);
      expect(
        (result.failingInput as double).abs(),
        lessThanOrEqualTo((result.originalFailingInput as double).abs()),
      );
      // Minimal failing case should be just > 1.0 or just < -1.0
      expect(
        (result.failingInput as double).abs(),
        closeTo(1.0, 0.5),
        reason: 'Should shrink close to the failure boundary 1.0',
      );
    });

    test('Gen.string shrinks by removing chars respecting minLength', () async {
      final minLength = 3;
      final runner = PropertyTestRunner(
        Gen.string(minLength: minLength, maxLength: 10),
        (value) {
          if (value.length > 5) {
            // Fail if longer than 5
            fail('String "$value" is too long');
          }
        },
        PropertyConfig(numTests: 50), // Ensure hitting a failing case
      );
      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.failingInput, isNotNull);
      final shrunkString = result.failingInput as String;
      expect(
        shrunkString.length,
        lessThanOrEqualTo((result.originalFailingInput as String).length),
      );
      expect(
        shrunkString.length,
        greaterThanOrEqualTo(minLength),
        reason: "Should respect minLength",
      );
      // Minimal failing string should be just over the boundary
      expect(
        shrunkString.length,
        closeTo(6, 1),
        reason: 'Should shrink to the minimal failing length 6',
      );
    });

    test('Gen.string shrinks by simplifying chars', () async {
      final runner = PropertyTestRunner(
        Gen.string(minLength: 1, maxLength: 5),
        (value) {
          if (value.contains(RegExp(r'[b-zB-Z1-9]'))) {
            // Fail if contains chars other than a, A, 0
            fail('String "$value" contains non-minimal chars');
          }
        },
        PropertyConfig(numTests: 50), // Ensure hitting a failing case
      );
      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.failingInput, isNotNull);
      final shrunkString = result.failingInput as String;
      // Minimal failing string should still fail the condition, but be simpler
      expect(
        shrunkString.contains(RegExp(r'[b-zB-Z1-9]')),
        isTrue,
        reason: "Shrunk string must still fail",
      );
      expect(
        shrunkString.length,
        lessThanOrEqualTo((result.originalFailingInput as String).length),
      );
      expect(shrunkString.length, greaterThanOrEqualTo(1));
      // It should be simpler - either shorter OR fewer non-'aA0' chars than original
      final originalBadChars = RegExp(
        r'[b-zB-Z1-9]',
      ).allMatches(result.originalFailingInput as String).length;
      final shrunkBadChars = RegExp(
        r'[b-zB-Z1-9]',
      ).allMatches(shrunkString).length;
      expect(
        shrunkString.length < (result.originalFailingInput as String).length ||
            shrunkBadChars < originalBadChars,
        isTrue,
        reason: "Shrinking should reduce length or complexity",
      );
    });
  });

  group('Gen.frequency', () {
    test('selects generators based on weight', () async {
      final gen = Gen.frequency([
        (9, Gen.constant('A')), // 90% chance
        (1, Gen.constant('B')), // 10% chance
      ]);
      int countA = 0;
      int countB = 0;
      final runner = PropertyTestRunner(gen, (value) {
        if (value == 'A') countA++;
        if (value == 'B') countB++;
      }, PropertyConfig(numTests: 200)); // Run enough times for stats

      await runner.run();

      expect(countA, greaterThan(150)); // Should be around 180
      expect(countB, greaterThan(5)); // Should be around 20
      expect(countB, lessThan(50));
      expect(countA + countB, equals(200));
    });

    test('shrinks using the chosen generator', () async {
      // Generate 'long_string' with high probability, 'short' with low
      final gen = Gen.frequency([
        (1, Gen.constant('short')),
        (
          9,
          Gen.string(minLength: 10, maxLength: 10),
        ), // Generate a 10-char string
      ]);

      final runner = PropertyTestRunner(
        gen,
        (value) {
          // Fail if the string is long to trigger shrinking
          if (value.length > 5) {
            fail('String too long: $value');
          }
        },
        PropertyConfig(numTests: 20),
      ); // Run enough times to likely get long string

      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.originalFailingInput, isA<String>());
      expect((result.originalFailingInput as String).length, equals(10));

      // The shrunk value should be from the string generator's shrinking,
      // likely a shorter string, not 'short'.
      expect(result.failingInput, isA<String>());
      expect((result.failingInput as String).length, lessThanOrEqualTo(10));
      expect(
        (result.failingInput as String).length,
        greaterThanOrEqualTo(6),
      ); // Should shrink towards the boundary length 5+1
      expect(result.failingInput, isNot(equals('short')));
    });

    test('throws ArgumentError for empty list', () {
      expect(() => Gen.frequency([]), throwsArgumentError);
    });

    test('throws ArgumentError for non-positive weights', () {
      expect(() => Gen.frequency([(0, Gen.constant(1))]), throwsArgumentError);
      expect(() => Gen.frequency([(-1, Gen.constant(1))]), throwsArgumentError);
      expect(
        () => Gen.frequency([(1, Gen.constant(1)), (0, Gen.constant(2))]),
        throwsArgumentError,
      );
    });
  });
}
