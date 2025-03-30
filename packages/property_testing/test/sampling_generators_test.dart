import 'package:property_testing/property_testing.dart';
import 'package:property_testing/src/generators/gen.dart';
import 'package:test/test.dart';
import 'dart:math';

void main() {
  group('Sampling Generators (pick, someOf, atLeastOne)', () {
    final options = ['a', 'b', 'c', 'd', 'e'];

    // --- Gen.pick ---
    group('Gen.pick', () {
      test('generates lists of the specified size', () async {
        final n = 3;
        final gen = Gen.pick(n, options);
        final runner = PropertyTestRunner(gen, (value) {
          expect(value, isA<List<String>>());
          expect(value.length, equals(n));
        }, PropertyConfig(numTests: 50));
        final result = await runner.run();
        expect(result.success, isTrue);
      });

      test('generates lists with unique elements from options', () async {
        final n = options.length; // Pick all
        final gen = Gen.pick(n, options);
        final runner = PropertyTestRunner(gen, (value) {
          expect(value.toSet().length, equals(n), reason: 'Elements should be unique');
          for (final item in value) {
            expect(options, contains(item));
          }
          // Check content equality ignoring order
          expect(value.toSet(), equals(options.toSet()));
        }, PropertyConfig(numTests: 20));
        final result = await runner.run();
        expect(result.success, isTrue);
      });

      test('generates empty list when n is 0', () async {
         final gen = Gen.pick(0, options);
         final runner = PropertyTestRunner(gen, (value) {
           expect(value, isEmpty);
         }, PropertyConfig(numTests: 5));
         final result = await runner.run();
         expect(result.success, isTrue);
      });

      test('throws ArgumentError for invalid n', () {
         expect(() => Gen.pick(-1, options), throwsArgumentError);
         expect(() => Gen.pick(options.length + 1, options), throwsArgumentError);
      });

       test('throws ArgumentError for empty options', () {
          expect(() => Gen.pick(0, []), throwsArgumentError);
       });

      test('shrinks by removing elements or simplifying choice', () async {
         final failingOptions = [10, 20, 30, 40, 50];
         final gen = Gen.pick(3, failingOptions);

         final runner = PropertyTestRunner(gen, (value) {
           // Fail if the list contains 40 *and* 50
           if (value.contains(40) && value.contains(50)) {
             fail('Contains both 40 and 50');
           }
         }, PropertyConfig(numTests: 50)); // Run enough to likely hit failure

         final result = await runner.run();
         expect(result.success, isFalse);
         final original = result.originalFailingInput as List<int>;
         final shrunk = result.failingInput as List<int>;

         expect(shrunk.length, equals(3)); // Size must remain the same for pick
         expect(shrunk.contains(40), isTrue); // Must still contain failing elements
         expect(shrunk.contains(50), isTrue);

         // Check if it simplified the *other* element(s)
         final originalOther = original.where((x) => x != 40 && x != 50).toList();
         final shrunkOther = shrunk.where((x) => x != 40 && x != 50).toList();

         expect(shrunkOther.length, equals(originalOther.length));
         if (shrunkOther.isNotEmpty) {
           // Expect the other element to be replaced by an earlier option (10, 20, or 30)
           expect(shrunkOther.first, lessThan(originalOther.first));
         }
      });
    });

    // --- Gen.someOf ---
    group('Gen.someOf', () {
      test('generates lists within specified size range', () async {
        final min = 1;
        final max = 3;
        final gen = Gen.someOf(options, min: min, max: max);
        final runner = PropertyTestRunner(gen, (value) {
          expect(value, isA<List<String>>());
          expect(value.length, greaterThanOrEqualTo(min));
          expect(value.length, lessThanOrEqualTo(max));
        }, PropertyConfig(numTests: 50));
        final result = await runner.run();
        expect(result.success, isTrue);
      });

       test('generates lists with unique elements from options', () async {
         final gen = Gen.someOf(options); // Default min=0, max=options.length
         final runner = PropertyTestRunner(gen, (value) {
           expect(value.toSet().length, equals(value.length), reason: 'Elements should be unique');
           for (final item in value) {
             expect(options, contains(item));
           }
         }, PropertyConfig(numTests: 50));
         final result = await runner.run();
         expect(result.success, isTrue);
       });

      test('uses default min/max correctly', () async {
         final gen = Gen.someOf(options);
         bool sawEmpty = false;
         bool sawFull = false;
         final runner = PropertyTestRunner(gen, (value) {
            expect(value.length, lessThanOrEqualTo(options.length));
            if (value.isEmpty) sawEmpty = true;
            if (value.length == options.length) sawFull = true;
         }, PropertyConfig(numTests: 100));
         await runner.run();
         expect(sawEmpty, isTrue);
         expect(sawFull, isTrue);
      });

      test('throws ArgumentError for invalid min/max', () {
          expect(() => Gen.someOf(options, min: -1), throwsArgumentError);
          expect(() => Gen.someOf(options, max: options.length + 1), throwsArgumentError);
          expect(() => Gen.someOf(options, min: 3, max: 2), throwsArgumentError);
      });

       test('throws ArgumentError for empty options', () {
          expect(() => Gen.someOf([]), throwsArgumentError);
       });

      test('shrinks by removing elements (respecting min)', () async {
         final min = 1;
         final gen = Gen.someOf(options, min: min, max: 4);
         final runner = PropertyTestRunner(gen, (value) {
           // Fail if list has more than 2 elements
           if (value.length > 2) {
             fail('List too long');
           }
         }, PropertyConfig(numTests: 50));

         final result = await runner.run();
         expect(result.success, isFalse);
         final original = result.originalFailingInput as List<String>;
         final shrunk = result.failingInput as List<String>;

         expect(shrunk.length, lessThanOrEqualTo(original.length));
         expect(shrunk.length, greaterThanOrEqualTo(min));
         // Minimal failing case should be just above the boundary
         expect(shrunk.length, closeTo(3, 1)); // Should shrink towards length 3
      });
    });

    // --- Gen.atLeastOne ---
    group('Gen.atLeastOne', () {
       test('generates non-empty lists', () async {
         final gen = Gen.atLeastOne(options);
         final runner = PropertyTestRunner(gen, (value) {
           expect(value, isNotEmpty);
           expect(value.length, lessThanOrEqualTo(options.length));
           expect(value.toSet().length, equals(value.length));
            for (final item in value) {
              expect(options, contains(item));
            }
         }, PropertyConfig(numTests: 50));
         final result = await runner.run();
         expect(result.success, isTrue);
       });

       test('is equivalent to someOf with min=1', () async {
         // Generate values from both and check if distributions seem similar (approx test)
         final gen1 = Gen.atLeastOne(options);
         final gen2 = Gen.someOf(options, min: 1);
         final lengths1 = <int>[];
         final lengths2 = <int>[];

         await PropertyTestRunner(gen1, (v) => lengths1.add(v.length), PropertyConfig(numTests: 100)).run();
         await PropertyTestRunner(gen2, (v) => lengths2.add(v.length), PropertyConfig(numTests: 100)).run();

         final avgLen1 = lengths1.fold(0, (s, l) => s + l) / lengths1.length;
         final avgLen2 = lengths2.fold(0, (s, l) => s + l) / lengths2.length;

         expect(lengths1, isNot(anyElement(equals(0)))); // No empty lists
         expect(lengths2, isNot(anyElement(equals(0))));
         expect(avgLen1, closeTo(avgLen2, 0.5)); // Average lengths should be similar
       });

        test('throws ArgumentError for empty options', () {
           expect(() => Gen.atLeastOne([]), throwsArgumentError);
        });
    });
  });
}