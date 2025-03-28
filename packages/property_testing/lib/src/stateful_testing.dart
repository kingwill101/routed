import 'dart:async';

import 'generator_base.dart';
import 'primitive_generators.dart';
import 'property_test_runner.dart';

/// Represents a command that can be executed against a system under test
abstract class Command<Model, Sut> {
  /// Check if this command can be run in the current state
  bool precondition(Model model) => true;

  /// Run the command against the system under test
  FutureOr<void> run(Sut sut);

  /// Update the model to reflect the expected state after running this command
  Model update(Model model);

  /// Check that the system under test matches the model after running this command
  FutureOr<void> postcondition(Model model, Sut sut);

  /// Get a string representation of this command for debugging
  @override
  String toString();
}

/// A sequence of commands to be executed against a system under test
class CommandSequence<Model, Sut> {
  final List<Command<Model, Sut>> commands;

  CommandSequence(this.commands);

  /// Run all commands in sequence against the system under test
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
class StatefulPropertyConfig extends PropertyConfig {
  /// The maximum number of commands to generate per test case
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

  /// Add a command generator to this builder
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

  /// Set the configuration for this builder
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

  /// Run the stateful property test
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
extension StatefulPropertyTestingExtensions<T> on Generator<T> {
  /// Filter commands based on their precondition
  Generator<T> whereValid<Model>(
    Model Function() getModel,
    bool Function(T, Model) isValid,
  ) {
    return where((value) => isValid(value, getModel()));
  }
}

class StatefulPropertyRunner<Model, Command> {
  final Generator<Command> commandGen;
  final Model Function() initialState;
  final bool Function(Model) invariant;
  final Model Function(Model, Command) update;
  final StatefulPropertyConfig config;

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
