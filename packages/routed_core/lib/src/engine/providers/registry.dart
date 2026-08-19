import 'package:routed_core/src/provider/provider.dart';
import 'package:routed_core/src/support/named_registry.dart';

import 'core.dart';
import 'routing.dart';
import 'uploads.dart';

typedef ServiceProviderFactory = ServiceProvider Function();

class ProviderRegistration {
  ProviderRegistration({
    required this.id,
    required this.factory,
    required this.description,
  });

  final String id;
  final ServiceProviderFactory factory;
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

  static final ProviderRegistry instance = ProviderRegistry._();

  void _registerDefaults() {
    register(
      'routed.core',
      factory: () => CoreServiceProvider(),
      description: 'Core services: typed engine configuration and bindings.',
    );
    register(
      'routed.routing',
      factory: () => RoutingServiceProvider(),
      description: 'Routing events and event manager bindings.',
    );
    register(
      'routed.uploads',
      factory: () => UploadsServiceProvider(),
      description: 'Multipart upload configuration defaults.',
    );
  }

  Iterable<ProviderRegistration> get registrations =>
      entries.values.toList(growable: false);

  ProviderRegistration? resolve(String id) => getEntry(id);

  bool has(String id) => containsEntry(id);

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
