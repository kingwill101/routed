
library;
/// A property-based testing framework for Dart inspired by Hypothesis and ScalaCheck.
///
/// Provides tools for generating random data based on specified constraints,
/// running tests against this data, and automatically shrinking failing test
/// cases to find minimal reproducible examples.
///
/// Core components include:
/// - **Generators:** Create values for testing (see `Gen`, `Specialized`, `Chaos`).
///   - Use combinators like `.map`, `.flatMap`, `.where`, `.list` to build complex generators.
/// - **Runner:** `PropertyTestRunner` executes tests and handles shrinking.
/// - **Configuration:** `PropertyConfig` controls test execution (number of runs, seed, etc.).
/// - **Stateful Testing:** Tools for testing systems over sequences of operations.
///
/// Example:
/// ```dart
/// import 'package:property_testing/property_testing.dart';
/// import 'package:test/test.dart';
///
/// void main() {
///   test('string length property', () async {
///     // Generate strings up to 50 characters
///     final stringGen = Gen.string(maxLength: 50);
///
///     // Test runner with the generator and property function
///     final runner = PropertyTestRunner(
///       stringGen,
///       (s) {
///         // Property: the length should be within bounds
///         expect(s.length, lessThanOrEqualTo(50));
///         expect(s.length, greaterThanOrEqualTo(0));
///       },
///       PropertyConfig(numTests: 200, seed: 42), // Configure test runs
///     );
///
///     // Run the test and check the result
///     final result = await runner.run();
///     expect(result.success, isTrue, reason: result.report);
///   });
/// }
/// ```

// Core
export 'src/generator_base.dart' show Generator, ShrinkableValue;
export 'src/property_test_runner.dart' show PropertyTestRunner, PropertyConfig, PropertyResult;

// Generators
export 'src/primitive_generators.dart' show Gen;
export 'src/specialized_generators.dart' show Specialized, Color, DateTimeGenerator, DurationGenerator, EmailGenerator, SemverGenerator, UriGenerator; // Also export Color type
export 'src/chaos_generators.dart' show Chaos, ChaosConfig, ChaosCategory;

// Stateful Testing
export 'src/stateful_testing.dart' show Command, CommandSequence, StatefulPropertyBuilder, StatefulPropertyConfig, StatefulPropertyRunner, StatefulPropertyTestingExtensions;

// Reporting
export 'src/test_reporter.dart' show PropertyTestReporter, TestStatisticsCollector, PropertyResultExtensions;
