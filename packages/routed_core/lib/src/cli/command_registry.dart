import 'package:routed_core/src/container/container.dart';
import 'package:routed_core/src/support/named_registry.dart';

/// Creates an application CLI command from the bootstrapped engine container.
///
/// The return type is intentionally opaque to `routed_core`: the CLI package
/// owns the concrete command type, while service providers can register their
/// commands without depending on `routed_cli`.
typedef CliCommandFactory = Object Function(Container container);

/// Describes one service-provider-owned CLI command.
final class CliCommandRegistration {
  /// Creates a CLI command registration.
  CliCommandRegistration({
    required this.id,
    required this.factory,
    this.description = '',
  });

  /// Stable provider-specific registration identifier.
  final String id;

  /// Creates the command after the application container has booted.
  final CliCommandFactory factory;

  /// Optional description used by discovery and diagnostics.
  final String description;
}

/// Per-engine registry for service-provider-owned CLI commands.
///
/// Registrations live with the application engine rather than in a process-wide
/// global. This allows a CLI invocation to bootstrap the same providers as the
/// server and discover the commands they expose without creating a dependency
/// from runtime packages back to `routed_cli`.
final class CliCommandRegistry extends NamedRegistry<CliCommandRegistration> {
  /// Creates an empty CLI command registry.
  CliCommandRegistry();

  /// Registers a command factory under [id].
  bool register(
    String id, {
    required CliCommandFactory factory,
    String description = '',
    bool overrideExisting = true,
  }) {
    return registerEntry(
      id,
      CliCommandRegistration(
        id: id,
        factory: factory,
        description: description,
      ),
      overrideExisting: overrideExisting,
    );
  }

  /// Removes a registration by identifier.
  bool unregister(String id) => unregisterEntry(id);

  /// Returns a snapshot of registered commands.
  Iterable<CliCommandRegistration> get registrations =>
      entries.values.toList(growable: false);
}
