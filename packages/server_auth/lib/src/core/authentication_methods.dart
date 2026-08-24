import 'dart:async';

const int _maxAuthenticationMethodContributors = 64;
const int _maxAuthenticationMethodsPerContributor = 256;
const int _maxAuthenticationMethodsPerUser = 1024;

/// Built-in kinds understood by the account-safety inventory.
enum AuthAuthenticationMethodKind {
  /// A password-backed credential.
  password,

  /// An account linked through an external OAuth provider.
  oauthProvider,

  /// A WebAuthn or passkey credential.
  passkey,

  /// A phone-number authentication method.
  phone,

  /// A one-time password delivered through email.
  emailOtp,

  /// An email-link authentication method.
  emailLink,

  /// A username-backed authentication method.
  username,

  /// An API key that is eligible to authenticate as the user.
  apiKey,

  /// An authentication method supplied by another plugin.
  plugin,
}

/// One usable way for a user to establish a new authenticated principal.
///
/// Method references are process-internal capability data. They contain no
/// credential material and deliberately have no serialization contract.
final class AuthAuthenticationMethod {
  AuthAuthenticationMethod._({
    required this.kind,
    required String namespace,
    required String id,
    required String identity,
    this.canAuthenticate = true,
    String? providerId,
    String? providerAccountId,
  }) : namespace = _component(namespace, 'namespace', maxLength: 64),
       id = _component(id, 'id', maxLength: 512),
       identity = _component(identity, 'identity', maxLength: 768),
       providerId = providerId == null
           ? null
           : _component(providerId, 'providerId', maxLength: 256),
       providerAccountId = providerAccountId == null
           ? null
           : _component(providerAccountId, 'providerAccountId', maxLength: 512);

  /// Creates a password method for [credentialId].
  factory AuthAuthenticationMethod.password(
    String credentialId, {
    String providerId = 'credentials',
  }) => AuthAuthenticationMethod._(
    kind: AuthAuthenticationMethodKind.password,
    namespace: 'password:$providerId',
    id: credentialId,
    identity: 'credential:$credentialId',
  );

  /// Creates an OAuth method for a provider account.
  factory AuthAuthenticationMethod.oauthProvider({
    required String providerId,
    required String providerAccountId,
    bool canAuthenticate = true,
  }) => AuthAuthenticationMethod._(
    kind: AuthAuthenticationMethodKind.oauthProvider,
    namespace: 'oauth',
    id: '$providerId:$providerAccountId',
    identity: _compoundIdentity('oauth', [providerId, providerAccountId]),
    canAuthenticate: canAuthenticate,
    providerId: providerId,
    providerAccountId: providerAccountId,
  );

  /// Creates a passkey method for [credentialId].
  factory AuthAuthenticationMethod.passkey(String credentialId) =>
      AuthAuthenticationMethod._(
        kind: AuthAuthenticationMethodKind.passkey,
        namespace: 'webauthn',
        id: credentialId,
        identity: 'webauthn:$credentialId',
      );

  /// Creates a phone method for [phoneNumber].
  factory AuthAuthenticationMethod.phone(String phoneNumber) =>
      AuthAuthenticationMethod._(
        kind: AuthAuthenticationMethodKind.phone,
        namespace: 'phone_number',
        id: phoneNumber,
        identity: 'phone_number:$phoneNumber',
      );

  /// Creates an email OTP method for [userId].
  factory AuthAuthenticationMethod.emailOtp(String userId) =>
      AuthAuthenticationMethod._(
        kind: AuthAuthenticationMethodKind.emailOtp,
        namespace: 'email_otp',
        id: userId,
        identity: 'email_otp:$userId',
      );

  /// Creates an email-link method for [userId] and [providerId].
  factory AuthAuthenticationMethod.emailLink({
    required String providerId,
    required String userId,
  }) => AuthAuthenticationMethod._(
    kind: AuthAuthenticationMethodKind.emailLink,
    namespace: 'email:$providerId',
    id: userId,
    identity: _compoundIdentity('email', [providerId, userId]),
  );

  /// A username and its password credential are one underlying login method.
  ///
  /// Sharing the password credential identity prevents the same credential
  /// from being counted twice when both credential and username plugins are
  /// installed.
  factory AuthAuthenticationMethod.username(String credentialId) =>
      AuthAuthenticationMethod._(
        kind: AuthAuthenticationMethodKind.username,
        namespace: 'username',
        id: credentialId,
        identity: 'credential:$credentialId',
      );

  /// Creates an API-key method for [keyId].
  factory AuthAuthenticationMethod.apiKey(String keyId) =>
      AuthAuthenticationMethod._(
        kind: AuthAuthenticationMethodKind.apiKey,
        namespace: 'api_key',
        id: keyId,
        identity: 'api_key:$keyId',
      );

  /// Creates a method supplied by a future plugin.
  factory AuthAuthenticationMethod.plugin({
    required String namespace,
    required String id,
  }) => AuthAuthenticationMethod._(
    kind: AuthAuthenticationMethodKind.plugin,
    namespace: namespace,
    id: id,
    identity: _compoundIdentity('plugin', [namespace, id]),
  );

  /// Kind of authentication method represented by this value.
  final AuthAuthenticationMethodKind kind;

  /// Stable namespace owned by one provider or server plugin.
  final String namespace;

  /// Store-local identity used only to distinguish methods for one user.
  final String id;

  /// Canonical identity used to collapse two views of the same credential.
  final String identity;

  /// Whether this method can currently establish a new principal.
  ///
  /// Inactive external-provider links remain inventoried so they can be
  /// removed, but they never qualify as the fallback that makes removal safe.
  final bool canAuthenticate;

  /// Exact provider coordinates for [AuthAuthenticationMethodKind.oauthProvider].
  final String? providerId;

  /// Provider account coordinate for an OAuth method.
  final String? providerAccountId;

  @override
  bool operator ==(Object other) =>
      other is AuthAuthenticationMethod && identity == other.identity;

  @override
  int get hashCode => identity.hashCode;
}

/// A contributor's bounded view of one user's usable authentication methods.
final class AuthAuthenticationMethodSnapshot {
  /// Creates a complete snapshot containing [methods].
  ///
  /// A complete empty snapshot authoritatively reports that no usable method
  /// exists.
  AuthAuthenticationMethodSnapshot.complete(
    Iterable<AuthAuthenticationMethod> methods,
  ) : methods = List<AuthAuthenticationMethod>.unmodifiable(methods),
      isComplete = true;

  /// Creates a snapshot that cannot authoritatively enumerate methods.
  const AuthAuthenticationMethodSnapshot.unavailable()
    : methods = const <AuthAuthenticationMethod>[],
      isComplete = false;

  AuthAuthenticationMethodSnapshot._incomplete(
    Iterable<AuthAuthenticationMethod> methods,
  ) : methods = List<AuthAuthenticationMethod>.unmodifiable(methods),
      isComplete = false;

  /// Methods reported by the contributor.
  final List<AuthAuthenticationMethod> methods;

  /// Whether an empty [methods] list authoritatively means no method exists.
  final bool isComplete;
}

/// Typed provider/plugin capability for enumerating usable login methods.
///
/// Implementations return only methods that can establish a new principal.
/// Recovery artifacts, inactive credentials, and non-primary API keys do not
/// qualify. An adapter that cannot provide an authoritative view returns an
/// unavailable snapshot so destructive mutations fail closed.
abstract interface class AuthAuthenticationMethodInventoryContributor {
  /// Stable namespace owned by this contributor.
  String get authenticationMethodNamespace;

  /// Returns the usable methods for [userId].
  FutureOr<AuthAuthenticationMethodSnapshot> authenticationMethodsForUser(
    String userId,
  );
}

/// Backend affinity declared by authoritative inventory contributors.
///
/// Durable coordinators use this declaration to reject topologies containing
/// method stores that cannot participate in their transaction.
abstract interface class AuthAuthenticationMethodInventoryBinding {
  /// Store or coordinator that owns this contributor's method data.
  Object get authenticationMethodStore;

  /// Method kinds that this store can report authoritatively.
  Set<AuthAuthenticationMethodKind> get authenticationMethodKinds;
}

/// Optional switch for contributors whose method status is configuration-led.
abstract interface class AuthAuthenticationMethodInventoryControl {
  /// Whether this contributor should participate in inventory composition.
  bool get authenticationMethodInventoryEnabled;
}

/// Binds the immutable method topology to a durable mutation coordinator.
abstract interface class AuthAuthenticationMethodTopologyStore {
  /// Binds [contributors] to the store's mutation topology.
  void bindAuthenticationMethodInventory(
    Iterable<AuthAuthenticationMethodInventoryContributor> contributors,
  );
}

/// Result of an atomic authentication-method removal attempt.
enum AuthAuthenticationMethodMutationResult {
  /// The target method was removed.
  mutated,

  /// No matching method was found.
  notFound,

  /// Removing the target would leave no usable authentication method.
  lastAuthenticationMethod,

  /// The store could not provide the required atomicity guarantee.
  atomicityUnavailable,
}

/// Loads the current authentication-method inventory for a user.
typedef AuthAuthenticationMethodInventoryLoader =
    FutureOr<AuthAuthenticationMethodSnapshot> Function();

/// Applies a previously checked authentication-method mutation.
typedef AuthAuthenticationMethodMutation = FutureOr<bool> Function();

/// Root-store transaction required by destructive method mutations.
///
/// The store invokes `loadInventory` and `mutate` in one serializable boundary
/// shared by every participating provider/plugin store. Durable adapters must
/// not implement this contract unless all nested stores join that transaction.
abstract interface class AuthAuthenticationMethodMutationStore {
  /// Mutates [target] only when [loadInventory] proves it is safe.
  FutureOr<AuthAuthenticationMethodMutationResult>
  mutateAuthenticationMethodIfSafe({
    required String userId,
    required AuthAuthenticationMethod target,
    required AuthAuthenticationMethodInventoryLoader loadInventory,
    required AuthAuthenticationMethodMutation mutate,
  });
}

/// Backend-owned exact OAuth unlink transaction.
///
/// Unlike the process-local mutation contract, this operation contains no
/// callback. The store itself checks the authoritative inventory and removes
/// the exact provider/account pair in one serializable boundary.
abstract interface class AuthOAuthAccountMutationStore {
  /// Unlinks the exact provider account when the mutation is safe.
  FutureOr<AuthAuthenticationMethodMutationResult> unlinkOAuthAccountIfSafe({
    required String userId,
    required String providerId,
    required String providerAccountId,
    required AuthAuthenticationMethodInventoryLoader loadInventory,
  });
}

/// Composes provider and plugin inventories with the root-store transaction.
final class AuthAuthenticationMethodService {
  /// Creates a service for the supplied root [store].
  ///
  /// Optional capabilities are discovered from [store]. Contributors supplied
  /// here are composed together with contributors passed to
  /// [composeContributors].
  AuthAuthenticationMethodService({
    required Object store,
    Iterable<AuthAuthenticationMethodInventoryContributor> contributors =
        const <AuthAuthenticationMethodInventoryContributor>[],
    Iterable<String> historicalAuthenticationMethodNamespaces = const [],
  }) : _mutationStore = store is AuthAuthenticationMethodMutationStore
           ? store
           : null,
       _oauthAccountMutationStore = store is AuthOAuthAccountMutationStore
           ? store
           : null,
       _topologyStore = store is AuthAuthenticationMethodTopologyStore
           ? store
           : null,
       _baseContributors = List.unmodifiable(contributors),
       _historicalAuthenticationMethodNamespaces =
           _normalizeHistoricalAuthenticationMethodNamespaces(
             historicalAuthenticationMethodNamespaces,
           );

  final AuthAuthenticationMethodMutationStore? _mutationStore;
  final AuthOAuthAccountMutationStore? _oauthAccountMutationStore;
  final AuthAuthenticationMethodTopologyStore? _topologyStore;
  final List<AuthAuthenticationMethodInventoryContributor> _baseContributors;
  final Set<String> _historicalAuthenticationMethodNamespaces;
  List<AuthAuthenticationMethodInventoryContributor> _contributors = const [];
  bool _composed = false;
  bool _historicalNamespaceTopologyComplete = true;

  /// Finalizes the inventory after plugin topology registration.
  void composeContributors(
    Iterable<AuthAuthenticationMethodInventoryContributor> contributors,
  ) {
    if (_composed) {
      throw StateError('Authentication method inventory is already composed.');
    }
    final combined =
        <AuthAuthenticationMethodInventoryContributor>[
              ..._baseContributors,
              ...contributors,
            ]
            .where((contributor) {
              return switch (contributor) {
                AuthAuthenticationMethodInventoryControl(
                  :final authenticationMethodInventoryEnabled,
                ) =>
                  authenticationMethodInventoryEnabled,
                _ => true,
              };
            })
            .toList(growable: false);
    if (combined.length > _maxAuthenticationMethodContributors) {
      throw StateError('Too many authentication method contributors.');
    }
    final namespaces = <String>{};
    for (final contributor in combined) {
      final namespace = _component(
        contributor.authenticationMethodNamespace,
        'authenticationMethodNamespace',
        maxLength: 64,
      );
      if (!namespaces.add(namespace)) {
        throw StateError(
          'Authentication method namespace "$namespace" is duplicated.',
        );
      }
    }
    _historicalNamespaceTopologyComplete = namespaces.containsAll(
      _historicalAuthenticationMethodNamespaces,
    );
    _topologyStore?.bindAuthenticationMethodInventory(combined);
    _contributors = List.unmodifiable(combined);
    _composed = true;
  }

  /// Returns a bounded aggregate snapshot without mutating storage.
  Future<AuthAuthenticationMethodSnapshot> snapshotForUser(String userId) {
    _ensureComposed();
    return _loadInventory(_component(userId, 'userId', maxLength: 512));
  }

  /// Removes [target] only when another known usable method remains.
  Future<AuthAuthenticationMethodMutationResult> removeIfSafe({
    required String userId,
    required AuthAuthenticationMethod target,
    required AuthAuthenticationMethodMutation mutate,
  }) async {
    _ensureComposed();
    final store = _mutationStore;
    if (store == null) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final normalizedUserId = _component(userId, 'userId', maxLength: 512);
    return store.mutateAuthenticationMethodIfSafe(
      userId: normalizedUserId,
      target: target,
      loadInventory: () => _loadInventory(normalizedUserId),
      mutate: mutate,
    );
  }

  /// Atomically removes one exact external-provider account.
  Future<AuthAuthenticationMethodMutationResult> removeOAuthAccountIfSafe({
    required String userId,
    required String providerId,
    required String providerAccountId,
  }) async {
    _ensureComposed();
    final store = _oauthAccountMutationStore;
    if (store == null) {
      return AuthAuthenticationMethodMutationResult.atomicityUnavailable;
    }
    final normalizedUserId = _component(userId, 'userId', maxLength: 512);
    final normalizedProviderId = _component(
      providerId,
      'providerId',
      maxLength: 256,
    );
    final normalizedProviderAccountId = _component(
      providerAccountId,
      'providerAccountId',
      maxLength: 512,
    );
    return store.unlinkOAuthAccountIfSafe(
      userId: normalizedUserId,
      providerId: normalizedProviderId,
      providerAccountId: normalizedProviderAccountId,
      loadInventory: () => _loadInventory(normalizedUserId),
    );
  }

  Future<AuthAuthenticationMethodSnapshot> _loadInventory(String userId) async {
    final methods = <String, AuthAuthenticationMethod>{};
    var complete = _historicalNamespaceTopologyComplete;
    for (final contributor in _contributors) {
      AuthAuthenticationMethodSnapshot snapshot;
      try {
        snapshot = await contributor.authenticationMethodsForUser(userId);
      } catch (_) {
        complete = false;
        continue;
      }
      if (!snapshot.isComplete) complete = false;
      if (snapshot.methods.length > _maxAuthenticationMethodsPerContributor) {
        complete = false;
        continue;
      }
      final namespace = contributor.authenticationMethodNamespace;
      for (final method in snapshot.methods) {
        if (method.namespace != namespace) {
          complete = false;
          continue;
        }
        if (methods.length >= _maxAuthenticationMethodsPerUser) {
          complete = false;
          break;
        }
        methods.putIfAbsent(method.identity, () => method);
      }
    }
    final values = methods.values;
    return complete
        ? AuthAuthenticationMethodSnapshot.complete(values)
        : AuthAuthenticationMethodSnapshot._incomplete(values);
  }

  void _ensureComposed() {
    if (!_composed) {
      throw StateError('Authentication method inventory is not composed.');
    }
  }
}

String _component(String value, String name, {required int maxLength}) {
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized != value ||
      normalized.length > maxLength ||
      normalized.contains(RegExp(r'[\u0000-\u001f\u007f]'))) {
    throw ArgumentError.value(value, name, 'must be a bounded safe value');
  }
  return normalized;
}

Set<String> _normalizeHistoricalAuthenticationMethodNamespaces(
  Iterable<String> values,
) {
  final namespaces = <String>{};
  for (final value in values) {
    final namespace = _component(
      value,
      'historicalAuthenticationMethodNamespaces',
      maxLength: 64,
    );
    if (!namespaces.add(namespace)) {
      throw ArgumentError.value(
        values,
        'historicalAuthenticationMethodNamespaces',
        'must contain unique namespace values',
      );
    }
  }
  return Set<String>.unmodifiable(namespaces);
}

String _compoundIdentity(String prefix, List<String> components) =>
    '$prefix:${components.map((value) => '${value.length}:$value').join()}';
