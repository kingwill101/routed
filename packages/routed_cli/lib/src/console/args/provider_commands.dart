import 'package:artisanal/args.dart';
// Provider registration intentionally uses this low-level registry contract;
// package:routed_core does not expose the registry through its public barrel.
// ignore: implementation_imports
import 'package:routed_core/src/support/named_registry.dart';

/// Creates an args-based command registered by a provider.
typedef ProviderCommandFactory = Command<void> Function();

/// Creates an Artisanal command registered by a provider.
typedef ProviderArtisanalCommandFactory = Command<void> Function();

/// Metadata for an args-based provider command.
class ProviderCommandRegistration {
  /// Creates a registration for [factory] under [id].
  ProviderCommandRegistration({
    required this.id,
    required this.factory,
    this.description = '',
  });

  /// Stable provider-specific identifier.
  final String id;

  /// Factory that creates the command.
  final ProviderCommandFactory factory;

  /// Description used when reporting the registration.
  final String description;
}

/// Metadata for an Artisanal provider command.
class ProviderArtisanalCommandRegistration {
  /// Creates a registration for [factory] under [id].
  ProviderArtisanalCommandRegistration({
    required this.id,
    required this.factory,
    this.description = '',
  });

  /// Stable provider-specific identifier.
  final String id;

  /// Factory that creates the command.
  final ProviderArtisanalCommandFactory factory;

  /// Description used when reporting the registration.
  final String description;
}

/// Registry for provider-registered args-based commands.
class ProviderCommandRegistry
    extends NamedRegistry<ProviderCommandRegistration> {
  ProviderCommandRegistry._();

  /// The process-wide provider command registry.
  static final ProviderCommandRegistry instance = ProviderCommandRegistry._();

  /// Registers a command factory and returns whether it was accepted.
  /// Registers an Artisanal command factory under [id].
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

  /// Removes the registration identified by [id].
  bool unregister(String id) => unregisterEntry(id);

  /// Returns the current command registrations.
  Iterable<ProviderCommandRegistration> get registrations =>
      entries.values.toList(growable: false);
}

/// Registry for provider-registered artisanal command factories.
class ProviderArtisanalCommandRegistry
    extends NamedRegistry<ProviderArtisanalCommandRegistration> {
  ProviderArtisanalCommandRegistry._();

  /// The process-wide Artisanal provider command registry.
  static final ProviderArtisanalCommandRegistry instance =
      ProviderArtisanalCommandRegistry._();

  /// Registers an Artisanal command factory under [id].
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

  /// Removes the registration identified by [id].
  bool unregister(String id) => unregisterEntry(id);

  /// Returns the current Artisanal command registrations.
  Iterable<ProviderArtisanalCommandRegistration> get registrations =>
      entries.values.toList(growable: false);
}

/// Registers provider commands with the given [runner].
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

/// Registers provider artisanal commands with the given [runner].
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
