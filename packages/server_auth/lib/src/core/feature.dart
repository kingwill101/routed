import 'store.dart';

/// Context supplied while an auth feature is being composed.
///
/// Feature-specific configuration belongs on the feature instance. The
/// context exposes only the shared persistence boundary so features do not
/// depend on a framework adapter or a global registry.
class AuthFeatureContext<TContext> {
  const AuthFeatureContext({required this.store});

  final AuthStore store;
}

/// Composable server-side auth capability.
///
/// A feature is the future home for a complete concern such as credentials,
/// passkeys, two-factor authentication, API keys, or organizations. The
/// initial contract is intentionally small: features have stable IDs and are
/// configured through a typed store context. Endpoint and hook registration
/// can be added without changing the persistence boundary.
abstract interface class AuthFeature<TContext> {
  String get id;

  void configure(AuthFeatureContext<TContext> context);
}

/// Registry for the features active in one auth runtime.
class AuthFeatureRegistry<TContext> {
  AuthFeatureRegistry({required AuthStore store}) : _store = store;

  final AuthStore _store;
  final Map<String, AuthFeature<TContext>> _features =
      <String, AuthFeature<TContext>>{};

  /// Registers and configures [feature]. Feature IDs must be unique.
  void register(AuthFeature<TContext> feature) {
    final id = feature.id.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(feature.id, 'feature.id', 'must not be empty');
    }
    if (_features.containsKey(id)) {
      throw StateError('Auth feature "$id" is already registered.');
    }

    _features[id] = feature;
    feature.configure(AuthFeatureContext<TContext>(store: _store));
  }

  /// Returns the feature with [id], if configured.
  AuthFeature<TContext>? find(String id) => _features[id.trim()];

  /// Whether a feature with [id] is configured.
  bool contains(String id) => find(id) != null;

  /// The configured features in registration order.
  Iterable<AuthFeature<TContext>> get values =>
      List<AuthFeature<TContext>>.unmodifiable(_features.values);
}
