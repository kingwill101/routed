import 'dart:math';

import 'package:property_testing/property_testing.dart';
import 'package:test/test.dart';

void main() {
  group('Email Generator', () {
    test('generates valid email addresses with default settings', () async {
      final runner = PropertyTestRunner(Specialized.email(), (email) {
        expect(email, contains('@'));
        final parts = email.split('@');
        expect(parts.length, equals(2));
        expect(parts[0], isNotEmpty);
        expect(parts[1], isNotEmpty);
        expect(parts[1], contains('.'));
      });

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('respects domain constraints', () async {
      final domains = ['example.com', 'test.org'];

      final runner = PropertyTestRunner(Specialized.email(domains: domains), (
        email,
      ) {
        final domain = email.split('@')[1];
        expect(domains, contains(domain));
      });

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('respects maximum local part length', () async {
      const maxLength = 32;

      final runner = PropertyTestRunner(
        Specialized.email(maxLocalPartLength: maxLength),
        (email) {
          final localPart = email.split('@')[0];
          expect(localPart.length, lessThanOrEqualTo(maxLength));
        },
      );

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('generates valid local parts', () async {
      final runner = PropertyTestRunner(Specialized.email(), (email) {
        final localPart = email.split('@')[0];
        // RFC 5322 allows for a lot of characters, but we're being conservative
        expect(localPart, matches(r'^[a-zA-Z0-9._-]+$'));
        expect(localPart, isNot(startsWith('.')));
        expect(localPart, isNot(endsWith('.')));
        expect(localPart, isNot(contains('..')));
      }, PropertyConfig(numTests: 1000));

      final result = await runner.run();
      expect(result.success, isTrue);
    });

    test('shrinks while maintaining valid email format', () async {
      final runner = PropertyTestRunner(Specialized.email(), (email) {
        // Force failure to trigger shrinking
        fail('Triggering shrink');
      });

      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.failingInput, isNotNull);

      final shrunkEmail = result.failingInput as String;
      expect(shrunkEmail, contains('@'));
      final parts = shrunkEmail.split('@');
      expect(parts.length, equals(2));
      expect(parts[0], isNotEmpty);
      expect(parts[1], isNotEmpty);
      expect(parts[1], contains('.'));
    });

    test('generates reproducible emails from the same seed', () async {
      final random = Random(42); // Use a specific seed for reproducibility
      final config = PropertyConfig(numTests: 10, random: random);
      final generator = Specialized.email(
        domains: ['example.com'],
        maxLocalPartLength: 10,
      );

      final emails1 = <String>[];
      final runner1 = PropertyTestRunner(
        generator,
        (email) => emails1.add(email),
        config,
      );
      await runner1.run();

      // Create a new random with the same seed
      final random2 = Random(42);
      final config2 = PropertyConfig(numTests: 10, random: random2);
      final emails2 = <String>[];
      final runner2 = PropertyTestRunner(
        generator,
        (email) => emails2.add(email),
        config2,
      );
      await runner2.run();

      expect(emails1, equals(emails2));
    });

    test('generates diverse local parts', () async {
      final seenChars = <String>{};
      final seenLengths = <int>{};

      final runner = PropertyTestRunner(Specialized.email(), (email) {
        final localPart = email.split('@')[0];
        seenChars.addAll(localPart.split(''));
        seenLengths.add(localPart.length);
      }, PropertyConfig(numTests: 1000));

      await runner.run();

      // We should see a good distribution of characters and lengths
      expect(
        seenChars.length,
        greaterThan(20),
      ); // Should see many different characters
      expect(
        seenLengths.length,
        greaterThan(10),
      ); // Should see many different lengths
    });

    test('handles edge cases', () async {
      final random = Random(42);
      final config = PropertyConfig(numTests: 100, random: random);
      final runner = PropertyTestRunner(
        Specialized.email(maxLocalPartLength: 1),
        (email) {
          // final localPart = email.split('@')[0]; // Removed unused variable
          try {
            expect(
              email.split('@')[0].length,
              equals(1),
            ); // Use expression directly
            expect(
              email,
              matches(r'^[a-zA-Z0-9]@'),
            ); // Only one alphanumeric character before @
          } catch (e) {
            print('Failed with email: $email');
            rethrow;
          }
        },
        config,
      );

      final result = await runner.run();
      if (!result.success) {
        final email = result.failingInput;
        // final localPart = email.split('@')[0]; // Unused
        fail(
          'Email validation failed for maxLocalPartLength=1: $email. Error: ${result.error}',
        );
      }
      expect(result.success, isTrue);
    });

    test('generates valid emails according to basic RFC 5322', () async {
      final runner = PropertyTestRunner(Specialized.email(), (email) {
        // This is a simplified RFC 5322 check
        expect(
          email,
          matches(r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'),
        );
        expect(email.length, lessThanOrEqualTo(254)); // Maximum total length

        final parts = email.split('@');
        expect(
          parts[0].length,
          lessThanOrEqualTo(64),
        ); // Maximum local part length
        expect(
          parts[1].length,
          lessThanOrEqualTo(255),
        ); // Maximum domain length
      }, PropertyConfig(numTests: 1000));

      final result = await runner.run();
      if (!result.success) {
        fail(
          'Test failed: ${result.error}\nInput: ${result.failingInput}\nOriginal input: ${result.originalFailingInput}',
        );
      }
      expect(result.success, isTrue);
    });
  });
}
