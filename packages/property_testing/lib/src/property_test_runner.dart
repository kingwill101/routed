import 'dart:async';
import 'dart:math' show Random;

import 'generator_base.dart';

/// A Random implementation that always uses the same seed
class _DefaultRandom implements Random {
  final Random _random;

  _DefaultRandom() : _random = Random(42);

  @override
  bool nextBool() => _random.nextBool();

  @override
  double nextDouble() => _random.nextDouble();

  @override
  int nextInt(int max) => _random.nextInt(max);
}

/// Configuration for property testing
/// Configuration options for controlling the execution of property tests.
///
/// Defines parameters such as the number of tests to run (`numTests`), the
/// maximum number of shrink attempts (`maxShrinks`), an optional execution
/// `timeout` per test case, and the `random` number generator to use for
/// reproducibility.
///
/// ```dart
/// final config = PropertyConfig(
///   numTests: 500,
///   maxShrinks: 50,
///   timeout: const Duration(seconds: 5),
///   random: Random(12345), // For reproducible runs
/// );
/// ```
class PropertyConfig {
  /// The number of test cases to run
  /// The total number of test cases executed before the test finished
  /// (either by passing the configured number of tests or by failing).

  /// The number of successful test cases that must run for the property
  /// to be considered passed.
  /// Defaults to 100.
  final int numTests;

  /// The maximum number of shrink attempts
  /// The maximum number of shrinking steps to perform when a failing
  /// test case is found. Controls how much effort is spent minimizing
  /// the failure.
  /// Defaults to 100.
  final int maxShrinks;

  /// The timeout for each test case
  /// An optional maximum duration allowed for a single execution of the
  /// property function. If the execution exceeds this duration, it's
  /// considered a failure.
  final Duration? timeout;

  /// The random number generator to use for test case generation
  /// The random number generator used for generating test inputs.
  /// Providing a generator with a fixed seed ensures reproducible test runs.
  /// If not provided, a default generator with a fixed seed (42) is used.
  final Random random;

  /// The seed used for the random number generator. If a [random] instance
  /// is provided directly, this might be null. If null, a default seed (42)
  /// or a system-generated one might be used internally. Reporting this helps
  /// in reproducing test runs.
  final int? seed;

  PropertyConfig({
      this.numTests = 100,
      this.maxShrinks = 100,
      this.timeout,
      Random? random,
      this.seed,
    }) : random = random ?? (seed != null ? Random(seed) : _DefaultRandom());
}

/// The result of a property test
/// Represents the outcome of executing a property test using [PropertyTestRunner].
///
/// Contains information about whether the test `success`ded, the number of
/// `numTests` run, details about the failure (`failingInput`,
/// `originalFailingInput`, `error`, `stackTrace`), and the number of
/// `numShrinks` performed if a failure occurred.
class PropertyResult {
  /// Whether the property passed all test cases
  /// `true` if the property held for all generated test cases, `false` otherwise.
  final bool success;

  /// The number of test cases that passed
  final int numTests;

  /// The failing input, if any
  /// If the test failed, this holds the minimal input value (after shrinking)
  /// that caused the failure. `null` if the test succeeded.
  final dynamic failingInput;

  /// The original failing input before shrinking, if any
  /// If the test failed, this holds the first input value discovered that
  /// caused the failure, before any shrinking was performed. `null` if the
  /// test succeeded.
  final dynamic originalFailingInput;

  /// The error that caused the failure, if any
  /// If the test failed, this holds the error or exception thrown by the
  /// property function for the [failingInput]. `null` if the test succeeded.
  final Object? error;

  /// The stack trace of the error, if any
  /// If the test failed, this holds the stack trace associated with the
  /// [error]. `null` if the test succeeded.
  final StackTrace? stackTrace;

  /// The number of shrink attempts made
  /// If the test failed, this indicates the number of successful shrinking
  /// steps performed to minimize the failing input. `0` if the test succeeded
  /// or no shrinking occurred.
  final int numShrinks;

  /// The seed used for the random number generator during this test run.
  /// Can be used to reproduce the exact sequence of generated values.
  final int? seed;

  const PropertyResult({
      required this.success,
      required this.numTests,
      this.failingInput,
      this.originalFailingInput,
      this.error,
      this.stackTrace,
      this.numShrinks = 0,
      this.seed,
    });
}

/// A runner for property tests
/// Executes a property test for a given generator and property function.
///
/// Takes a `generator` to produce input values of type [T], a `property`
/// function to test against each generated value, and an optional `config`
/// ([PropertyConfig]) to control execution.
///
/// The [run] method executes the test loop: generating values, running the
/// property, and attempting to shrink any failures found. It returns a
/// [PropertyResult] summarizing the outcome.
///
/// ```dart
/// import 'package:property_testing/property_testing.dart';
/// import 'package:test/test.dart';
///
/// void main() {
///   test('addition is commutative', () async {
///     final runner = PropertyTestRunner(
///       Gen.integer().list(minLength: 2, maxLength: 2),
///       (pair) {
///         expect(pair[0] + pair[1], equals(pair[1] + pair[0]));
///       },
///       PropertyConfig(numTests: 500),
///     );
///
///     final result = await runner.run();
///     expect(result.success, isTrue, reason: result.report);
///   });
/// }
/// ```
class PropertyTestRunner<T> {
  final Generator<T> generator;
  final FutureOr<void> Function(T) property;
  final PropertyConfig config;

  /// Creates a new property test runner.
  ///
  /// Requires a [generator] to produce inputs of type [T] and a [property]
  /// function that takes an input of type [T] and performs assertions.
  /// The [property] function should return `void` or `Future<void>`.
  /// An optional [config] can be provided to customize test execution.
  PropertyTestRunner(this.generator, this.property, [PropertyConfig? config])
      : config = config ?? PropertyConfig();

  /// Runs the property test according to the configuration.
  ///
  /// Generates test cases using the provided [generator], executes the
  /// [property] function for each case, and performs shrinking if a failure
  /// is detected.
  ///
  /// Returns a [PropertyResult] summarizing the outcome.
  Future<PropertyResult> run() async {
    for (var i = 0; i < config.numTests; i++) {
      final value = generator.generate(config.random);
      try {
        final result = property(value.value);
        if (result is Future) {
          if (config.timeout != null) {
            await result.timeout(config.timeout!);
          } else {
            await result;
          }
        }
      } catch (e, st) {
        // Found a failing case, try to shrink it
        final shrinkResult = await _shrink(value, e, st);
        return PropertyResult(
                  success: false,
                  numTests: i + 1,
                  failingInput: shrinkResult.shrunkValue,
                  originalFailingInput: value.value,
                  error: shrinkResult.error,
                  stackTrace: shrinkResult.stackTrace,
                  numShrinks: shrinkResult.numShrinks,
                  seed: config.seed, // Pass the seed used
                );
      }
    }

    return PropertyResult(
          success: true,
          numTests: config.numTests,
          seed: config.seed, // Pass the seed used
        );
  }

  Future<_ShrinkResult<T>> _shrink(
    ShrinkableValue<T> value,
    Object error,
    StackTrace stackTrace,
  ) async {
    var currentValue = value;
    var currentError = error;
    var currentStackTrace = stackTrace;
    var numShrinks = 0;

    // Try to shrink the value while preserving the failure
    shrinkLoop:
    for (var i = 0; i < config.maxShrinks; i++) {
      final shrinks = currentValue.shrinks().toList();
      if (shrinks.isEmpty) {
        break;
      }

      // Try each possible shrink
      for (final shrink in shrinks) {
        try {
          final result = property(shrink.value);
          if (result is Future) {
            if (config.timeout != null) {
              await result.timeout(config.timeout!);
            } else {
              await result;
            }
          }
        } catch (e, st) {
          // Found a smaller failing case
          currentValue = shrink;
          currentError = e;
          currentStackTrace = st;
          numShrinks++;
          continue shrinkLoop;
        }
      }

      // No smaller failing cases found
      break;
    }

    return _ShrinkResult(
      shrunkValue: currentValue.value,
      error: currentError,
      stackTrace: currentStackTrace,
      numShrinks: numShrinks,
    );
  }
}

class _ShrinkResult<T> {
  final T shrunkValue;
  final Object error;
  final StackTrace stackTrace;
  final int numShrinks;

  _ShrinkResult({
    required this.shrunkValue,
    required this.error,
    required this.stackTrace,
    required this.numShrinks,
  });
}
