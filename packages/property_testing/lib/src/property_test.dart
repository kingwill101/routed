import 'dart:math' as math;
import 'package:property_testing/src/property_tester.dart';
import 'package:test/test.dart';

/// A [PropertyTester] that generates inputs using a provided generator
/// and checks if a given property holds true for all generated inputs.
///
/// Uses an exploration phase to generate and test inputs, followed by
/// a shrinking phase to minimize failing test cases if any are found.
class ForAllTester<T> implements PropertyTester {
  /// The generator function used to create test inputs of type [T].
  /// This should produce [ShrinkableValue] instances that can be tested
  /// and potentially shrunk to simpler failing cases.
  final Generator<T> generator;

  /// Configuration parameters controlling the test exploration and shrinking phases.
  /// Determines number of test runs, input sizes, and shrinking behavior.
  ExploreConfig config;

  /// Creates a new property tester that will use [generator] to produce test inputs.
  ///
  /// The optional [config] parameter customizes the testing behavior. If omitted,
  /// default configuration values will be used.
  ForAllTester(this.generator, {ExploreConfig? config})
      : config = config ?? ExploreConfig();

  /// Tests that the given [property] holds true for generated test inputs.
  ///
  /// Generates a series of test inputs and verifies that [property] executes
  /// without errors for each one. If a failing case is found, attempts to shrink
  /// it to a simpler failing example.
  ///
  /// Throws an error if any test case fails, with details about the failing input.
  @override
  Future<void> check(Future<void> Function(T input) property) async {
    dynamic failingInput;
    ShrinkableValue<T>? failingShrinkable;
    int shrinkCount = 0;
    bool foundFailing = false;

    // Exploration Phase
    for (var run = 0; run < config.numRuns; run++) {
      // Generate an input
      final size = config.initialSize + (run * config.speed);
      final shrinkable = generator(config.random, size);
      final input = shrinkable.value;

      try {
        // Execute the test and check the property
        await property(input);
      } catch (e) {
        foundFailing = true;
        failingInput = input;
        failingShrinkable = shrinkable;
        print('\nFailed for input: $input');
        print('Error: $e');
        break; // Break out of the exploration phase
      }
    }

    // Shrinking Phase
    if (foundFailing && failingShrinkable != null) {
      dynamic shrunkInput = failingInput;
      ShrinkableValue<T> shrunkValue = failingShrinkable;
      while (shrunkValue.canShrink() && shrinkCount < config.maxShrinks) {
        dynamic nextValue = shrunkValue.shrink();
        try {
          await property(nextValue);
          // Test passes, update shrunkValue with shrunken input.
          shrunkInput = nextValue;
          shrinkCount++;
        } catch (e) {
          // Shrinking failed, stop shrinking and return failing value.
          break;
        }
      }
      expect(false, isTrue,
          reason:
              'Property failed after $shrinkCount shrinks for input: $shrunkInput');
    } else {
      print('\nProperty passed for all ${config.numRuns} inputs.');
    }
  }

  /// Tests that a given [invariant] holds true for all generated inputs.
  ///
  /// The [invariant] function should return true if the property holds for
  /// the given input, false otherwise.
  ///
  /// This is a convenience wrapper around [check] that converts boolean
  /// results into pass/fail test outcomes.
  @override
  Future<void> checkInvariant(Future<bool> Function(T input) invariant) async {
    await check((input) async {
      final result = await invariant(input);
      expect(result, isTrue, reason: 'Invariant failed for input: $input');
    });
  }

  /// Tests that two functions [f1] and [f2] produce equivalent results
  /// for all generated inputs.
  ///
  /// Both functions are called with the same generated input and their
  /// results are compared for equality.
  ///
  /// This is useful for testing that refactored code maintains the same
  /// behavior as the original implementation.
  @override
  Future<void> checkEquivalence(Future<dynamic> Function(T input) f1,
      Future<dynamic> Function(T input) f2) async {
    await check((input) async {
      final result1 = await f1(input);
      final result2 = await f2(input);
      expect(result1, equals(result2),
          reason: 'Functions not equivalent for input: $input');
    });
  }
}

/// Configuration options that control how property tests are executed.
///
/// This includes parameters for both the exploration phase (generating and testing inputs)
/// and the shrinking phase (minimizing failing examples).
class ExploreConfig {
  /// The starting size for generated test inputs.
  /// Higher values produce more complex initial test cases.
  final int initialSize;

  /// The number of test cases to generate and verify.
  /// Higher values provide more thorough testing but take longer to complete.
  final int numRuns;

  /// Controls how quickly the input size grows during testing.
  /// Higher values cause test cases to become complex more rapidly.
  final int speed;

  /// Maximum number of shrinking attempts when minimizing a failing test case.
  /// Higher values allow more thorough minimization but may take longer.
  final int maxShrinks;

  /// Random number generator used to create test inputs.
  /// Can be seeded for reproducible test runs.
  final math.Random random;

  /// Creates a test configuration with the specified parameters.
  ///
  /// All parameters are optional and have reasonable defaults:
  /// - [initialSize]: 10
  /// - [numRuns]: 100
  /// - [speed]: 1
  /// - [maxShrinks]: 200
  /// - [random]: Random(42)
  ExploreConfig({
    this.initialSize = 10,
    this.numRuns = 100,
    this.speed = 1,
    this.maxShrinks = 200,
    math.Random? random,
  }) : random = random ?? math.Random(42); // Default seed for reproducibility
}

/// Function type for generating test inputs.
///
/// Takes a random number generator and size parameter and produces
/// a [ShrinkableValue] containing the generated test case.
typedef Generator<T> = ShrinkableValue<T> Function(
    math.Random random, int size);

/// Base class for values that can be shrunk to simpler forms.
///
/// Shrinking allows failing test cases to be minimized to simpler
/// examples that still demonstrate the failure.
abstract class ShrinkableValue<T> {
  /// Creates a new shrinkable value wrapping [value].
  ShrinkableValue(this.value);

  /// The actual test value being wrapped.
  final T value;

  /// Whether this value can be shrunk further.
  ///
  /// Returns false by default - subclasses must override to enable shrinking.
  bool canShrink() {
    return false;
  }

  /// Attempts to produce a simpler version of this value.
  ///
  /// The specific shrinking strategy is determined by subclasses.
  dynamic shrink();
}

/// A concrete implementation of [ShrinkableValue] that maintains a list of
/// progressively simpler values to try during shrinking.
class DataShape<T> extends ShrinkableValue<T> {
  /// Creates a new data shape with the given [value] and optional [shrinkValues].
  ///
  /// The [shrinkValues] list provides candidate simpler values to try during
  /// the shrinking phase, from simplest to most complex.
  DataShape(super.value, {this.shrinkValues = const []});

  /// List of progressively simpler values to try during shrinking.
  final List<T> shrinkValues;

  @override
  dynamic shrink() {
    if (shrinkValues.isNotEmpty) {
      // Get the first shrink value, remove it from list
      final shrinkValue = shrinkValues.first;
      shrinkValues.removeAt(0);
      return shrinkValue;
    }
    return value;
  }
}
