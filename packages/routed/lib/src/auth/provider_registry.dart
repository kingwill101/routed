import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:routed/src/auth/providers.dart';
import 'package:routed/src/provider/config_utils.dart';
import 'package:routed/src/support/named_registry.dart';

/// Builds auth providers from config definitions.
class AuthProviderRegistration {
  const AuthProviderRegistration({
    required this.id,
    required this.schema,
    required this.builder,
  });

  final String id;
  final Schema schema;
  final AuthProvider? Function(Map<String, dynamic> config) builder;
}

/// Registry for auth provider configuration handlers.
class AuthProviderRegistry extends NamedRegistry<AuthProviderRegistration> {
  AuthProviderRegistry._();

  static final AuthProviderRegistry instance = AuthProviderRegistry._();

  bool register(
    AuthProviderRegistration registration, {
    bool overrideExisting = true,
  }) {
    return registerEntry(
      registration.id,
      registration,
      overrideExisting: overrideExisting,
    );
  }

  bool unregister(String name) => unregisterEntry(name);

  Iterable<AuthProviderRegistration> get registrations => entries.values;

  Map<String, Schema> schemaEntries() {
    final schemas = <String, Schema>{};
    for (final registration in registrations) {
      schemas[registration.id] = registration.schema;
    }
    return schemas;
  }

  List<AuthProvider> buildProviders(Map<String, dynamic> config) {
    final providers = <AuthProvider>[];
    for (final registration in registrations) {
      final raw = config[registration.id];
      if (raw == null) {
        continue;
      }
      final map = stringKeyedMap(
        raw as Object,
        'auth.providers.${registration.id}',
      );
      final provider = registration.builder(map);
      if (provider != null) {
        providers.add(provider);
      }
    }
    return providers;
  }
}
