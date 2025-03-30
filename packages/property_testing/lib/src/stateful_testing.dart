import 'dart:async';

import 'generator_base.dart';
import 'generators/gen.dart';
import 'property_test_runner.dart';

/// Represents a command that can be executed against a system under test
/// Represents a single operation or action that can be performed on a system
/// under test (SUT) in stateful property testing.
///
/// Commands encapsulate the logic for checking preconditions, executing the
/// action on the SUT, updating a simplified `Model` of the SUT's state, and
/// checking postconditions against the actual SUT state.
///
/// Implementations define specific actions within the system being tested.
///
/// ```dart
/// // Example command for a counter model/SUT
/// class IncrementCommand extends Command&lt;int, Counter> {
///   final int amount;
///   IncrementCommand(this.amount);
///
///   @override
///   bool precondition(int model) => true; // Always possible to increment
///
///   @override
///   FutureOr&lt;void> run(Counter sut) => sut.increment(amount);
///
///   @override
///   int update(int model) => model + amount;
///
///   @override
///   FutureOr&lt;void> postcondition(int model, Counter sut) {
///     expect(sut.count, equals(model));
///   }
///
///   @override
///   String toString() => 'Increment($amount)';
/// }
/// ```
abstract class Command<Model, Sut> {
  /// Check if this command can be run in the current state
  /// Checks if this command is valid to execute given the current abstract
  /// state represented by the [model].
  /// Defaults to `true`.
  bool precondition(Model model) => true;

  /// Run the command against the system under test
  /// Executes the command's action against the actual System Under Test [sut].
  /// Can be synchronous or asynchronous.
  FutureOr<void> run(Sut sut);

  /// Update the model to reflect the expected state after running this command
  /// Updates the abstract [model] state to reflect the expected state *after*
  /// this command has been successfully executed. This should mirror the
  /// state change in the [sut].
  Model update(Model model);

  /// Check that the system under test matches the model after running this command
  /// Verifies that the actual state of the [sut] matches the predicted state
  /// in the [model] *after* the command has executed. This typically involves
  /// assertions comparing properties of the [sut] and the [model].
  FutureOr<void> postcondition(Model model, Sut sut);

  /// Get a string representation of this command for debugging
  @override
  String toString();
}

/// A sequence of commands to be executed against a system under test
/// Represents a sequence of [Command] objects to be executed against a
/// system under test (SUT) during stateful property testing.
///
/// The sequence maintains the order of commands. The [run] method executes
/// each command sequentially, checking preconditions, running the command,
/// updating the model, and checking postconditions at each step.
class CommandSequence<Model, Sut> {
  final List<Command<Model, Sut>> commands;

  CommandSequence(this.commands);

  /// Executes the sequence of commands against the [sut], starting from the
    /// [initialModel] state.
    ///
    /// For each command, it:
    /// 1. Checks the [Command.precondition].
    /// 2. Executes [Command.run] on the [sut].
    /// 3. Updates the model state using [Command.update].
    /// 4. Verifies the state using [Command.postcondition].
    ///
    /// Throws a [StateError] if any precondition fails.
    Future<void> run(Model initialModel, Sut sut) async {
    var model = initialModel;

    for (final command in commands) {
      if (!command.precondition(model)) {
        throw StateError('Precondition failed for command: $command');
      }

      await command.run(sut);
      model = command.update(model);
      await command.postcondition(model, sut);
    }
  }

  @override
  String toString() => commands.join('\n');
}

/// Configuration for stateful property testing
/// Configuration options specifically for stateful property tests.
///
/// Extends [PropertyConfig] and adds options like `maxCommandSequenceLength`
/// to control the maximum number of commands generated in a single test sequence.
///
/// ```dart
/// final config = StatefulPropertyConfig(
///   maxCommandSequenceLength: 50,
///   numTests: 200,
///   random: Random(99),
/// );
/// ```
class StatefulPropertyConfig extends PropertyConfig {
  /// The maximum number of commands to generate per test case
  /// The maximum number of commands to generate in a single test sequence.
  /// Defaults to 100.
  final int maxCommandSequenceLength;

  StatefulPropertyConfig({
    this.maxCommandSequenceLength = 100,
    super.numTests = 100,
    super.maxShrinks = 100,
    super.timeout,
    super.random,
  });
}

/// A builder for creating stateful property tests
/// A fluent builder for constructing and running stateful property tests.
///
/// Configures the test by defining how to create the initial `Model`, how to
/// `setupSut` (System Under Test) and `teardownSut`, and providing command
/// generators via `withCommands`. The test execution parameters can be set
/// using `withConfig`.
///
/// The [run] method builds the necessary generators and executes the stateful
/// test using [PropertyTestRunner].
///
/// ```dart
/// // Assume Counter, IncrementCommand, DecrementCommand are defined
///
/// final builder = StatefulPropertyBuilder&lt;int, Counter>.create(
///   initialModel: () => 0,
///   setupSut: () async => Counter(),
///   teardownSut: (sut) async { /* cleanup */ },
/// )
///   .withCommands(Gen.integer(min: 1, max: 5).map((i) => IncrementCommand(i)))
///   .withCommands(Gen.integer(min: 1, max: 5).map((i) => DecrementCommand(i)))
///   .withConfig(StatefulPropertyConfig(numTests: 100));
///
/// final result = await builder.run();
/// expect(result.success, isTrue, reason: result.report);
/// ```
class StatefulPropertyBuilder<Model, Sut> {
  final Model Function() _initialModel;
  final Future<Sut> Function() _setupSut;
  final Future<void> Function(Sut) _teardownSut;
  final List<Generator<Command<Model, Sut>>> _commandGenerators;
  final StatefulPropertyConfig _config;

  StatefulPropertyBuilder._({
    required Model Function() initialModel,
    required Future<Sut> Function() setupSut,
    required Future<void> Function(Sut) teardownSut,
    List<Generator<Command<Model, Sut>>>? commandGenerators,
    StatefulPropertyConfig? config,
  })  : _initialModel = initialModel,
        _setupSut = setupSut,
        _teardownSut = teardownSut,
        _commandGenerators = commandGenerators ?? [],
        _config = config ?? StatefulPropertyConfig();

  /// Create a new stateful property test builder
  /// Creates a new builder instance.
  ///
  /// Requires functions to:
  /// - [initialModel]: Create a fresh instance of the model at the start of each test sequence.
  /// - [setupSut]: Create and initialize a fresh instance of the System Under Test.
  /// - [teardownSut]: Clean up the SUT instance after a test sequence completes.
  static StatefulPropertyBuilder<Model, Sut> create<Model, Sut>({
    required Model Function() initialModel,
    required Future<Sut> Function() setupSut,
    required Future<void> Function(Sut) teardownSut,
  }) {
    return StatefulPropertyBuilder._(
      initialModel: initialModel,
      setupSut: setupSut,
      teardownSut: teardownSut,
    );
  }

  /// Adds a generator that produces [Command] instances for the test.
    ///
    /// Multiple command generators can be added; the runner will typically choose
    /// between them randomly using [Gen.oneOfGen] during sequence generation.
    StatefulPropertyBuilder<Model, Sut> withCommands(
      Generator<Command<Model, Sut>> commandGenerator,
    ) {
    return StatefulPropertyBuilder._(
      initialModel: _initialModel,
      setupSut: _setupSut,
      teardownSut: _teardownSut,
      commandGenerators: [..._commandGenerators, commandGenerator],
      config: _config,
    );
  }

  /// Sets the [StatefulPropertyConfig] to use for this test run, overriding
    /// the default configuration.
    StatefulPropertyBuilder<Model, Sut> withConfig(
      StatefulPropertyConfig config,
    ) {
    return StatefulPropertyBuilder._(
      initialModel: _initialModel,
      setupSut: _setupSut,
      teardownSut: _teardownSut,
      commandGenerators: _commandGenerators,
      config: config,
    );
  }

  /// Builds the command sequence generator and runs the stateful property test.
    ///
    /// Returns a [PropertyResult] summarizing the outcome. Throws a [StateError]
    /// if no command generators were provided via [withCommands].
    Future<PropertyResult> run() async {
    if (_commandGenerators.isEmpty) {
      throw StateError('No command generators provided');
    }

    final sequenceGen = _buildSequenceGenerator();
    final runner = PropertyTestRunner(
      sequenceGen,
      (sequence) => _runSequence(sequence),
      _config,
    );

    return runner.run();
  }

  Generator<CommandSequence<Model, Sut>> _buildSequenceGenerator() {
    // Generate a random length between 1 and maxCommandSequenceLength
    final lengthGen =
        Gen.integer(min: 1, max: _config.maxCommandSequenceLength);

    // Generate a sequence of that length using the command generators
    return lengthGen.flatMap((length) {
      final commandGen = Gen.oneOfGen(_commandGenerators);
      return commandGen
          .list(minLength: length, maxLength: length)
          .map((commands) => CommandSequence(commands));
    });
  }

  Future<void> _runSequence(CommandSequence<Model, Sut> sequence) async {
    final sut = await _setupSut();
    try {
      await sequence.run(_initialModel(), sut);
    } finally {
      await _teardownSut(sut);
    }
  }
}

/// Extension methods for working with stateful property tests
/// Extension methods providing convenience functions for stateful property testing
/// scenarios, particularly related to command generation.
extension StatefulPropertyTestingExtensions<T> on Generator<T> {
  /// Filter commands based on their precondition
  Generator<T> whereValid<Model>(
    Model Function() getModel,
    bool Function(T, Model) isValid,
  ) {
    return where((value) => isValid(value, getModel()));
  }
}

/// A simplified runner for stateful property tests focusing on model-based invariants.
///
/// This runner is suitable when the primary goal is to verify that a sequence
/// of commands maintains a specific invariant on the model state, without needing
/// explicit setup/teardown or postcondition checks against a real SUT.
///
/// Takes a `commandGen`, an `initialState` function for the model, an
/// `invariant` function to check the model state, and an `update` function
/// to apply command effects to the model.
///
/// ```dart
/// // Example: Testing a simple counter model
/// final counterRunner = StatefulPropertyRunner&lt;int, int>(
///   Gen.oneOf([1, -1]), // Commands are just +1 or -1
///   () => 0,            // Initial state is 0
///   (model) => model >= 0, // Invariant: counter never negative
///   (model, command) => model + command, // Update: add command value
///   StatefulPropertyConfig(numTests: 500),
/// );
///
/// final result = await counterRunner.run();
/// expect(result.success, isTrue, reason: result.report);
/// ```
class StatefulPropertyRunner<Model, Command> {
  final Generator<Command> commandGen;
  final Model Function() initialState;
  final bool Function(Model) invariant;
  final Model Function(Model, Command) update;
  final StatefulPropertyConfig config;

  /// Creates a new stateful property runner using the invariant-based approach.
  ///
  /// - [commandGen]: Generator for the commands/operations to apply.
  /// - [initialState]: Function to create the initial model state.
  /// - [invariant]: Function to check if a model state is valid.
  /// - [update]: Function to apply the effect of a command to the model state.
  /// - [config]: Optional configuration for the test run.
  StatefulPropertyRunner(
    this.commandGen,
    this.initialState,
    this.invariant,
    this.update, [
    StatefulPropertyConfig? config,
  ]) : config = config ?? StatefulPropertyConfig();

  Future<PropertyResult> run() async {
    final runner = PropertyTestRunner(
      commandGen.list(maxLength: config.maxCommandSequenceLength),
      (commands) async {
        var model = initialState();
        if (!invariant(model)) {
          throw Exception('Initial state violates invariant');
        }

        for (final command in commands) {
          model = update(model, command);
          if (!invariant(model)) {
            throw Exception(
                'Command $command led to state violating invariant');
          }
        }
      },
      config,
    );

    return runner.run();
  }
}

/// The result of a stateful property test
// ... existing code ...
