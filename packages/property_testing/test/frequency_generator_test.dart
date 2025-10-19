import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';

void main() {
  group('Gen.frequency', () {
    test('selects generators based on weight', () async {
      final genA = Gen.constant('A');
      final genB = Gen.constant('B');
      final freqGen = Gen.frequency([
        (9, genA), // High weight for 'A'
        (1, genB), // Low weight for 'B'
      ]);

      int countA = 0;
      int countB = 0;
      final numRuns = 200;

      final runner = PropertyTestRunner(freqGen, (value) {
        if (value == 'A') countA++;
        if (value == 'B') countB++;
      }, PropertyConfig(numTests: numRuns));

      await runner.run();

      expect(countA + countB, equals(numRuns));
      // Expect countA to be roughly 9 times countB
      expect(countA / (countB + 1), greaterThan(5)); // Allow some variance
      expect(countA, greaterThan(numRuns * 0.7)); // Should be mostly A
      expect(countB, greaterThan(0)); // Should see some B
    });

    test('works with different generator types', () async {
      final freqGen = Gen.frequency([
        (1, Gen.integer(max: 0)), // Negative ints
        (1, Gen.integer(min: 1)), // Positive ints
        (1, Gen.constant(0)), // Zero
      ]);

      final values = <int>{};
      final runner = PropertyTestRunner(freqGen, (value) {
        values.add(value);
      }, PropertyConfig(numTests: 100));

      await runner.run();

      expect(values.any((v) => v < 0), isTrue);
      expect(values.any((v) => v > 0), isTrue);
      expect(values, contains(0));
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

    test('shrinking delegates to the chosen generator', () async {
      final failingGen = Gen.integer(
        min: 10,
        max: 20,
      ).where((x) => x > 15); // Fails if > 15
      final passingGen = Gen.constant(5);

      final freqGen = Gen.frequency([
        (1, failingGen), // This one will be chosen sometimes and fail
        (1, passingGen), // This one passes
      ]);

      final runner = PropertyTestRunner(
        freqGen,
        (value) {
          if (value > 15) {
            fail('Value $value is > 15');
          }
          // Property passes for value <= 15 (which includes 5 from passingGen)
        },
        PropertyConfig(numTests: 50),
      ); // Run enough to likely hit the failing gen

      final result = await runner.run();

      expect(result.success, isFalse);
      expect(result.originalFailingInput, greaterThan(15));
      expect(
        result.failingInput,
        greaterThan(15),
        reason: "Shrunk value must still fail",
      );
      // Crucially, the shrunk value should still be from the failingGen's domain (>=10),
      // not shrunk towards the passingGen's constant (5).
      expect(result.failingInput, greaterThanOrEqualTo(10));
      // It should be either 16 or 17 (close to the boundary of failing, which is >15)
      expect(result.failingInput, anyOf(equals(16), equals(17)));
    });

    test('handles complex nested frequency generators', () async {
      final leafGen = Gen.constant('leaf');
      final nestedFreq = Gen.frequency([
        (1, leafGen),
        (1, Gen.constant('nested')),
      ]);
      final topFreq = Gen.frequency([
        (1, nestedFreq),
        (1, Gen.constant('top')),
      ]);

      final values = <String>{};
      final runner = PropertyTestRunner(topFreq, (value) {
        values.add(value);
      }, PropertyConfig(numTests: 50));

      await runner.run();

      expect(values, contains('leaf'));
      expect(values, contains('nested'));
      expect(values, contains('top'));
    });
  });
}
