import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';
import 'dart:convert';

void main() {
  group('Chaos Generators', () {
    test('Chaos.string generates strings within length', () async {
      final minLength = 10;
      final maxLength = 50;
      final gen = Chaos.string(minLength: minLength, maxLength: maxLength);
      final runner = PropertyTestRunner(gen, (value) {
        // Check length based on runes (Unicode code points)
        expect(value.runes.length, greaterThanOrEqualTo(minLength),
            reason:
                "String runes length (${value.runes.length}) should be >= $minLength for value: '$value'");
        expect(value.runes.length, lessThanOrEqualTo(maxLength),
            reason:
                "String runes length (${value.runes.length}) should be <= $maxLength for value: '$value'");
        // Simple check: it should contain some non-ASCII or control chars usually
      }, PropertyConfig(numTests: 50));
      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('Chaos.string generates varied problematic chars', () async {
      final gen = Chaos.string(minLength: 5, maxLength: 20);
      final seenChars = <int>{};
      final runner = PropertyTestRunner(gen, (value) {
        for (var rune in value.runes) {
          seenChars.add(rune);
        }
      }, PropertyConfig(numTests: 100));
      await runner.run();
      // Expect to see some null bytes, control chars, maybe invalid unicode
      expect(seenChars, contains(0)); // Null byte
      expect(seenChars.any((c) => c > 127), isTrue); // Some non-ASCII
    });

    test('Chaos.integer generates edge cases and values within range',
        () async {
      final min = -50;
      final max = 50;
      final gen = Chaos.integer(min: min, max: max);
      final values = <int>{};
      final runner = PropertyTestRunner(gen, (value) {
        expect(value, greaterThanOrEqualTo(min));
        expect(value, lessThanOrEqualTo(max));
        values.add(value);
      }, PropertyConfig(numTests: 100));
      await runner.run();
      // Should include edge cases like 0, 1, -1 if within range
      expect(values, contains(0));
      expect(values, contains(1));
      expect(values, contains(-1));
      // Should also contain random values within the range
      expect(values.any((v) => v > 1 || v < -1), isTrue);
    });

    test('Chaos.integer respects min/max for edge cases', () async {
      final min = 10; // Min is above some edge cases like 0, 1, -1
      final max = 100;
      final gen = Chaos.integer(min: min, max: max);
      final runner = PropertyTestRunner(gen, (value) {
        expect(value, greaterThanOrEqualTo(min));
        expect(value, lessThanOrEqualTo(max));
        expect(
            value,
            isNot(isIn([
              0,
              1,
              -1
            ]))); // Should not generate clamped edge cases below min
      }, PropertyConfig(numTests: 100));
      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('Chaos.json generates potentially invalid but parsable structures',
        () async {
      final gen = Chaos.json(maxDepth: 3, maxLength: 5);
      int parseSuccess = 0;
      int parseFail = 0;
      final runner = PropertyTestRunner(gen, (value) {
        try {
          json.decode(value);
          parseSuccess++;
          // Further checks could be added here on the structure
        } catch (e) {
          parseFail++;
          // It's okay for chaos JSON to sometimes fail parsing,
          // but it shouldn't *always* fail
        }
      }, PropertyConfig(numTests: 100));
      await runner.run();
      expect(parseSuccess, greaterThan(0),
          reason: "Should successfully parse some JSON");
      // Allow more failures for chaos testing, e.g., up to 80%
      expect(parseFail, lessThan(80),
          reason: "Chaos JSON should sometimes be invalid, but not always");
    });

    test('Chaos.bytes generates byte lists within length', () async {
      final minLength = 5;
      final maxLength = 25;
      final gen = Chaos.bytes(minLength: minLength, maxLength: maxLength);
      final runner = PropertyTestRunner(gen, (value) {
        expect(value.length, greaterThanOrEqualTo(minLength));
        expect(value.length, lessThanOrEqualTo(maxLength));
        expect(value, isA<List<int>>());
      }, PropertyConfig(numTests: 50));
      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('Chaos.bytes includes problematic bytes', () async {
      final gen = Chaos.bytes(minLength: 10, maxLength: 30);
      final seenBytes = <int>{};
      final runner = PropertyTestRunner(gen, (value) {
        seenBytes.addAll(value);
      }, PropertyConfig(numTests: 100));
      await runner.run();
      expect(seenBytes, contains(0x00)); // Null byte
      expect(seenBytes, contains(0xFF)); // Max byte
      expect(seenBytes, contains(0x0A)); // LF
    });

    // Shrinking tests
    // Chaos shrinking is complex, basic checks:
    test('Chaos.string shrinks', () async {
      final runner = PropertyTestRunner(
          Chaos.string(minLength: 10),
          (s) => fail('Force shrink'),
          PropertyConfig(numTests: 1) // Run once to force failure
          );
      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.failingInput, isNotNull);
      expect((result.failingInput as String).length,
          lessThanOrEqualTo((result.originalFailingInput as String).length));
    });

    test('Chaos.integer shrinks', () async {
      final runner = PropertyTestRunner(
          Chaos.integer(min: -100, max: 100),
          (i) => fail('Force shrink'),
          PropertyConfig(numTests: 1) // Run once to force failure
          );
      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.failingInput, isNotNull);
      // Check if shrunk towards 0 or boundaries
      expect((result.failingInput as int).abs(),
          lessThanOrEqualTo((result.originalFailingInput as int).abs()));
    });
  });
}
