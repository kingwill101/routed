import 'package:artisanal/args.dart';
import 'package:routed/src/support/named_registry.dart';

typedef ProviderCommandFactory = Command<void> Function();
typedef ProviderArtisanalCommandFactory = Command<void> Function();

class ProviderCommandRegistration {
  ProviderCommandRegistration({
    required this.id,
    required this.factory,
    this.description = '',
  });

  final String id;
  final ProviderCommandFactory factory;
  final String description;
}

class ProviderArtisanalCommandRegistration {
  ProviderArtisanalCommandRegistration({
    required this.id,
    required this.factory,
    this.description = '',
  });

  final String id;
  final ProviderArtisanalCommandFactory factory;
  final String description;
}

/// Registry for provider-registered args-based commands.
class ProviderCommandRegistry
    extends NamedRegistry<ProviderCommandRegistration> {
  ProviderCommandRegistry._();

  static final ProviderCommandRegistry instance = ProviderCommandRegistry._();

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

  bool unregister(String id) => unregisterEntry(id);

  Iterable<ProviderCommandRegistration> get registrations =>
      entries.values.toList(growable: false);
}

/// Registry for provider-registered artisanal command factories.
class ProviderArtisanalCommandRegistry
    extends NamedRegistry<ProviderArtisanalCommandRegistration> {
  ProviderArtisanalCommandRegistry._();

  static final ProviderArtisanalCommandRegistry instance =
      ProviderArtisanalCommandRegistry._();

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

  bool unregister(String id) => unregisterEntry(id);

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
  final existingNames = <String>{};
  for (final command in runner.commands.values) {
    existingNames.add(command.name);
    existingNames.addAll(command.aliases);
  }
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
        'Provider command "${command.name}" conflicts with an existing command.',
        usage,
      );
    }
    runner.addCommand(command);
    existingNames.add(command.name);
    existingNames.addAll(command.aliases);
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
  final existingNames = <String>{};
  for (final command in runner.commands.values) {
    existingNames.add(command.name);
    existingNames.addAll(command.aliases);
  }
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
        'Provider command "${command.name}" conflicts with an existing command.',
        usage,
      );
    }
    runner.addCommand(command);
    existingNames.add(command.name);
    existingNames.addAll(command.aliases);
  }
}
