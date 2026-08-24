import 'package:routed_core/src/engine/providers/core.dart';
import 'package:routed_core/src/engine/providers/routing.dart';
import 'package:routed_core/src/engine/providers/uploads.dart';
import 'package:routed_core/src/provider/provider.dart';
import 'package:routed_core/src/support/named_registry.dart';

/// Creates a service provider instance.
typedef ServiceProviderFactory = ServiceProvider Function();

/// Metadata and factory for a registered service provider.
class ProviderRegistration {
  /// Creates provider registration metadata.
  ProviderRegistration({
    required this.id,
    required this.factory,
    required this.description,
  });

  /// The stable provider identifier.
  final String id;

  /// The factory used to create the provider.
  final ServiceProviderFactory factory;

  /// Human-readable provider description.
  final String description;
}

/// Registry of known service provider factories.
///
/// The registry is an explicit composition aid for applications and adapters.
/// It does not load providers from files or resolve string-based configuration.
class ProviderRegistry extends NamedRegistry<ProviderRegistration> {
  ProviderRegistry._() {
    _registerDefaults();
  }

  /// The process-wide registry of built-in and application providers.
  static final ProviderRegistry instance = ProviderRegistry._();

  void _registerDefaults() {
    register(
      'routed.core',
      factory: CoreServiceProvider.new,
      description: 'Core services: typed engine configuration and bindings.',
    );
    register(
      'routed.routing',
      factory: RoutingServiceProvider.new,
      description: 'Routing events and event manager bindings.',
    );
    register(
      'routed.uploads',
      factory: UploadsServiceProvider.new,
      description: 'Multipart upload configuration defaults.',
    );
  }

  /// The registered provider metadata in insertion order.
  Iterable<ProviderRegistration> get registrations =>
      entries.values.toList(growable: false);

  /// Resolves a provider registration by [id].
  ProviderRegistration? resolve(String id) => getEntry(id);

  /// Whether a provider with [id] is registered.
  bool has(String id) => containsEntry(id);

  /// Registers a provider factory under [id].
  void register(
    String id, {
    required ServiceProviderFactory factory,
    String description = '',
    bool overrideExisting = false,
  }) {
    if (containsEntry(id) && !overrideExisting) {
      return;
    }
    registerEntry(
      id,
      ProviderRegistration(id: id, factory: factory, description: description),
      overrideExisting: overrideExisting,
    );
  }
}
