import 'package:artisanal/args.dart';
// Provider registration intentionally uses this low-level registry contract;
// package:routed_core does not expose the registry through its public barrel.
// ignore: implementation_imports
import 'package:routed_core/src/support/named_registry.dart';

/// Creates an args-based command when a provider registration is consumed.
typedef ProviderCommandFactory = Command<void> Function();

/// Creates an Artisanal command when a provider registration is consumed.
typedef ProviderArtisanalCommandFactory = Command<void> Function();

/// Metadata used to expose one provider-owned command through a runner.
class ProviderCommandRegistration {
  /// Creates a registration for [factory] under [id].
  ProviderCommandRegistration({
    required this.id,
    required this.factory,
    this.description = '',
  });

  /// Stable provider-specific identifier.
  final String id;

  /// Factory invoked when the command is registered with a runner.
  final ProviderCommandFactory factory;

  /// Optional description used by provider discovery and diagnostics.
  final String description;
}

/// Metadata used to expose one Artisanal provider command through a runner.
class ProviderArtisanalCommandRegistration {
  /// Creates a registration for [factory] under [id].
  ProviderArtisanalCommandRegistration({
    required this.id,
    required this.factory,
    this.description = '',
  });

  /// Stable provider-specific identifier.
  final String id;

  /// Factory invoked when the command is registered with a runner.
  final ProviderArtisanalCommandFactory factory;

  /// Optional description used by provider discovery and diagnostics.
  final String description;
}

/// Process-wide registry for provider-registered args-based commands.
///
/// A provider can register a factory once and let an application attach the
/// resulting commands to its own [CommandRunner]:
///
/// ```dart
/// ProviderCommandRegistry.instance.register(
///   'reports',
///   factory: ReportsCommand.new,
///   description: 'Generate usage reports.',
/// );
/// registerProviderCommands(
///   runner,
///   ProviderCommandRegistry.instance.registrations,
///   runner.usage,
/// );
/// ```
class ProviderCommandRegistry
    extends NamedRegistry<ProviderCommandRegistration> {
  ProviderCommandRegistry._();

  /// The process-wide provider command registry.
  static final ProviderCommandRegistry instance = ProviderCommandRegistry._();

  /// Registers a command factory under [id].
  ///
  /// Returns `true` when the registry accepts the entry. When
  /// [overrideExisting] is `false`, an existing entry with the same identifier
  /// is retained and the method returns `false`.
  bool register(
    String id, {
    required ProviderCommandFactory factory,
    String description = '',
    bool overrideExisting = true,
  }) {
    return registerEntry(
      id,
      ProviderCommandRegistration(
        id: id,
        factory: factory,
        description: description,
      ),
      overrideExisting: overrideExisting,
    );
  }

  /// Removes the registration identified by [id] and returns whether it
  /// existed.
  bool unregister(String id) => unregisterEntry(id);

  /// Returns a snapshot of the current command registrations.
  Iterable<ProviderCommandRegistration> get registrations =>
      entries.values.toList(growable: false);
}

/// Process-wide registry for provider-registered Artisanal command factories.
class ProviderArtisanalCommandRegistry
    extends NamedRegistry<ProviderArtisanalCommandRegistration> {
  ProviderArtisanalCommandRegistry._();

  /// The process-wide Artisanal provider command registry.
  static final ProviderArtisanalCommandRegistry instance =
      ProviderArtisanalCommandRegistry._();

  /// Registers an Artisanal command factory under [id].
  ///
  /// Returns `true` when the registry accepts the entry. When
  /// [overrideExisting] is `false`, an existing entry with the same identifier
  /// is retained and the method returns `false`.
  bool register(
    String id, {
    required ProviderArtisanalCommandFactory factory,
    String description = '',
    bool overrideExisting = true,
  }) {
    return registerEntry(
      id,
      ProviderArtisanalCommandRegistration(
        id: id,
        factory: factory,
        description: description,
      ),
      overrideExisting: overrideExisting,
    );
  }

  /// Removes the registration identified by [id] and returns whether it
  /// existed.
  bool unregister(String id) => unregisterEntry(id);

  /// Returns a snapshot of the current Artisanal command registrations.
  Iterable<ProviderArtisanalCommandRegistration> get registrations =>
      entries.values.toList(growable: false);
}

/// Instantiates and adds provider commands to [runner].
///
/// The factory for each registration is invoked lazily. A factory failure or a
/// name/alias conflict throws a [UsageException] using [usage]; an empty
/// [registrations] iterable leaves the runner unchanged.
void registerProviderCommands(
  CommandRunner<void> runner,
  Iterable<ProviderCommandRegistration> registrations,
  String usage,
) {
  if (registrations.isEmpty) {
    return;
  }
  final existingNames = runner.commands.values
      .expand((command) => [command.name, ...command.aliases])
      .toSet();
  for (final registration in registrations) {
    Command<void> command;
    try {
      command = registration.factory();
    } catch (error) {
      throw UsageException(
        'Failed to load provider command "${registration.id}": $error',
        usage,
      );
    }
    final hasConflict =
        existingNames.contains(command.name) ||
        command.aliases.any(existingNames.contains);
    if (hasConflict) {
      throw UsageException(
        'Provider command "${command.name}" conflicts with an existing '
        'command.',
        usage,
      );
    }
    runner.addCommand(command);
    existingNames
      ..add(command.name)
      ..addAll(command.aliases);
  }
}

/// Instantiates and adds Artisanal provider commands to [runner].
///
/// This follows the same conflict and factory-error rules as
/// [registerProviderCommands], but consumes
/// [ProviderArtisanalCommandRegistration] values.
void registerProviderArtisanalCommands(
  CommandRunner<void> runner,
  Iterable<ProviderArtisanalCommandRegistration> registrations,
  String usage,
) {
  if (registrations.isEmpty) {
    return;
  }
  final existingNames = runner.commands.values
      .expand((command) => [command.name, ...command.aliases])
      .toSet();
  for (final registration in registrations) {
    Command<void> command;
    try {
      command = registration.factory();
    } catch (error) {
      throw UsageException(
        'Failed to load provider command "${registration.id}": $error',
        usage,
      );
    }
    final hasConflict =
        existingNames.contains(command.name) ||
        command.aliases.any(existingNames.contains);
    if (hasConflict) {
      throw UsageException(
        'Provider command "${command.name}" conflicts with an existing '
        'command.',
        usage,
      );
    }
    runner.addCommand(command);
    existingNames
      ..add(command.name)
      ..addAll(command.aliases);
  }
}

/// Registers an Artisanal command factory and returns whether it was accepted.
