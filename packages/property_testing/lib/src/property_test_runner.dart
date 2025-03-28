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
class PropertyConfig {
  /// The number of test cases to run
  final int numTests;

  /// The maximum number of shrink attempts
  final int maxShrinks;

  /// The timeout for each test case
  final Duration? timeout;

  /// The random number generator to use for test case generation
  final Random random;

  PropertyConfig({
    this.numTests = 100,
    this.maxShrinks = 100,
    this.timeout,
    Random? random,
  }) : random = random ?? _DefaultRandom();
}

/// The result of a property test
class PropertyResult {
  /// Whether the property passed all test cases
  final bool success;

  /// The number of test cases that passed
  final int numTests;

  /// The failing input, if any
  final dynamic failingInput;

  /// The original failing input before shrinking, if any
  final dynamic originalFailingInput;

  /// The error that caused the failure, if any
  final Object? error;

  /// The stack trace of the error, if any
  final StackTrace? stackTrace;

  /// The number of shrink attempts made
  final int numShrinks;

  const PropertyResult({
    required this.success,
    required this.numTests,
    this.failingInput,
    this.originalFailingInput,
    this.error,
    this.stackTrace,
    this.numShrinks = 0,
  });
}

/// A runner for property tests
class PropertyTestRunner<T> {
  final Generator<T> generator;
  final FutureOr<void> Function(T) property;
  final PropertyConfig config;

  PropertyTestRunner(this.generator, this.property, [PropertyConfig? config])
      : config = config ?? PropertyConfig();

  /// Run the property test
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
        );
      }
    }

    return PropertyResult(
      success: true,
      numTests: config.numTests,
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
