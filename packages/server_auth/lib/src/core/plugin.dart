import 'dart:async';

import 'models.dart';
import 'password_hasher.dart';
import 'password_policy.dart';
import 'rate_limit.dart';
import 'store.dart';

enum AuthOperationMethod { get, post }

enum AuthOperationAuthentication { none, session }

enum AuthOperationOriginPolicy { none, browser }

enum AuthOperationCsrfPolicy { none, required }

final class AuthOperationCodec<T> {
  const AuthOperationCodec({required this.decode, required this.encode});

  final T Function(Map<String, dynamic> json) decode;
  final Object? Function(T value) encode;
}

final class AuthOperationInvocation<TContext> {
  const AuthOperationInvocation({
    required this.context,
    required this.user,
    this.emailVerified = false,
    this.activeOrganizationId,
    this.activeTeamId,
    this.writeActiveSelection,
    this.sessionControl,
  });

  final TContext context;
  final AuthUser? user;
  final bool emailVerified;
  final String? activeOrganizationId;
  final String? activeTeamId;
  final FutureOr<void> Function(String? organizationId, String? teamId)?
  writeActiveSelection;
  final AuthServerPluginSessionControl? sessionControl;
}

/// A framework-neutral redirect returned by an auth plugin endpoint.
final class AuthEndpointRedirect {
  const AuthEndpointRedirect({
    required this.location,
    this.statusCode = 302,
    this.headers = const <String, String>{},
  });

  final Uri location;
  final int statusCode;
  final Map<String, String> headers;
}

/// Host-owned session operations available to portable plugin endpoints.
abstract interface class AuthServerPluginSessionControl {
  AuthSessionStrategy get strategy;
  String? get currentSessionId;
  FutureOr<AuthSession> replaceIdentity(
    AuthUser user, {
    required String authenticationMethod,
    Duration? maximumAge,
    String? impersonatedBy,
  });
  FutureOr<void> signOut();
}

enum AuthAuthenticationPolicyPhase { beforeSessionIssue, resolveSession }

final class AuthAuthenticationPolicyRequest<TContext> {
  const AuthAuthenticationPolicyRequest({
    required this.context,
    required this.user,
    required this.phase,
  });

  final TContext context;
  final AuthUser user;
  final AuthAuthenticationPolicyPhase phase;
}

/// Optional plugin contribution consulted at every authentication boundary.
abstract interface class AuthAuthenticationPolicyContributor<TContext> {
  FutureOr<void> enforceAuthenticationPolicy(
    AuthAuthenticationPolicyRequest<TContext> request,
  );
}

/// Plugin-owned user data that participates in administrative hard deletion.
abstract interface class AuthUserDataDeletionContributor {
  String get userDataNamespace;
  FutureOr<void> validateUserDeletion(String userId);
  FutureOr<void> deleteUserData(String userId);
}

/// Optional second-pass composition after every plugin has been registered.
abstract interface class AuthServerPluginTopologyAware<TContext> {
  void composePluginTopology(Iterable<AuthServerPlugin<TContext>> plugins);
}

abstract interface class AuthEndpointDescriptor<TContext> {
  String get id;
  AuthOperationMethod get method;
  String get path;
  AuthOperationAuthentication get authentication;
  AuthOperationOriginPolicy get originPolicy;
  AuthOperationCsrfPolicy get csrfPolicy;
  AuthRateLimitOperation? get rateLimitOperation;
  bool get serverOnly;

  FutureOr<Object?> invoke(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  );
}

final class TypedAuthEndpointDescriptor<TContext, TRequest, TResponse>
    implements AuthEndpointDescriptor<TContext> {
  const TypedAuthEndpointDescriptor({
    required this.id,
    required this.method,
    required this.path,
    required this.requestCodec,
    required this.responseCodec,
    required this.handler,
    this.authentication = AuthOperationAuthentication.session,
    this.originPolicy = AuthOperationOriginPolicy.browser,
    this.csrfPolicy = AuthOperationCsrfPolicy.none,
    this.rateLimitOperation,
    this.serverOnly = false,
  });

  @override
  final String id;
  @override
  final AuthOperationMethod method;
  @override
  final String path;
  final AuthOperationCodec<TRequest> requestCodec;
  final AuthOperationCodec<TResponse> responseCodec;
  final FutureOr<TResponse> Function(
    AuthOperationInvocation<TContext> invocation,
    TRequest request,
  )
  handler;
  @override
  final AuthOperationAuthentication authentication;
  @override
  final AuthOperationOriginPolicy originPolicy;
  @override
  final AuthOperationCsrfPolicy csrfPolicy;
  @override
  final AuthRateLimitOperation? rateLimitOperation;
  @override
  final bool serverOnly;

  @override
  Future<Object?> invoke(
    AuthOperationInvocation<TContext> invocation,
    Map<String, dynamic> input,
  ) async {
    final response = await handler(invocation, requestCodec.decode(input));
    return responseCodec.encode(response);
  }
}

abstract interface class AuthEndpointContributor<TContext> {
  Iterable<AuthEndpointDescriptor<TContext>> get endpoints;
}

abstract interface class AuthPersistenceContributor {
  Iterable<AuthPersistenceSchema> get persistenceSchemas;
}

abstract interface class AuthClientOperationContributor {
  Iterable<AuthClientOperationDescriptor> get clientOperations;
}

abstract interface class AuthRateLimitContributor {
  Iterable<AuthRateLimitOperation> get rateLimitOperations;
}

final class AuthClientOperationDescriptor {
  const AuthClientOperationDescriptor({
    required this.id,
    required this.method,
    required this.path,
    this.serverOnly = false,
  });

  final String id;
  final AuthOperationMethod method;
  final String path;
  final bool serverOnly;
}

final class AuthPersistenceSchema {
  const AuthPersistenceSchema({
    required this.id,
    required this.entities,
    this.atomicOperations = const <AuthAtomicOperationDescriptor>[],
  });

  final String id;
  final List<AuthEntityDescriptor> entities;
  final List<AuthAtomicOperationDescriptor> atomicOperations;
}

final class AuthEntityDescriptor {
  const AuthEntityDescriptor({
    required this.id,
    required this.fields,
    this.relationships = const <AuthRelationshipDescriptor>[],
    this.uniqueConstraints = const <List<String>>[],
    this.indexes = const <List<String>>[],
  });

  final String id;
  final List<AuthFieldDescriptor> fields;
  final List<AuthRelationshipDescriptor> relationships;
  final List<List<String>> uniqueConstraints;
  final List<List<String>> indexes;
}

final class AuthFieldDescriptor {
  const AuthFieldDescriptor({required this.name, required this.kind});

  final String name;
  final String kind;
}

final class AuthRelationshipDescriptor {
  const AuthRelationshipDescriptor({
    required this.field,
    required this.targetEntity,
    this.cascadeDelete = false,
  });

  final String field;
  final String targetEntity;
  final bool cascadeDelete;
}

final class AuthAtomicOperationDescriptor {
  const AuthAtomicOperationDescriptor({
    required this.id,
    required this.description,
  });

  final String id;
  final String description;
}

class AuthServerPluginContext<TContext> {
  const AuthServerPluginContext({
    required this.store,
    this.passwordHasher,
    this.passwordPolicy = const PasswordPolicy(),
    this.sessionStrategy = AuthSessionStrategy.session,
  });

  final AuthStore store;
  final PasswordHasher? passwordHasher;
  final PasswordPolicy passwordPolicy;
  final AuthSessionStrategy sessionStrategy;
}

abstract interface class AuthServerPlugin<TContext> {
  String get id;

  void configure(AuthServerPluginContext<TContext> context);
}

class AuthServerPluginRegistry<TContext> {
  AuthServerPluginRegistry({
    required AuthStore store,
    PasswordHasher? passwordHasher,
    PasswordPolicy passwordPolicy = const PasswordPolicy(),
    AuthSessionStrategy sessionStrategy = AuthSessionStrategy.session,
  }) : _store = store,
       _passwordHasher = passwordHasher ?? Argon2idPasswordHasher(),
       _passwordPolicy = passwordPolicy,
       _sessionStrategy = sessionStrategy;

  final AuthStore _store;
  final PasswordHasher _passwordHasher;
  final PasswordPolicy _passwordPolicy;
  final AuthSessionStrategy _sessionStrategy;
  final Map<String, AuthServerPlugin<TContext>> _plugins =
      <String, AuthServerPlugin<TContext>>{};
  final Map<String, AuthEndpointDescriptor<TContext>> _endpoints =
      <String, AuthEndpointDescriptor<TContext>>{};
  final Set<String> _endpointKeys = <String>{};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  void register(AuthServerPlugin<TContext> plugin) {
    if (_frozen) throw StateError('Auth plugin topology is frozen.');
    final id = plugin.id.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(plugin.id, 'plugin.id', 'must not be empty');
    }
    if (_plugins.containsKey(id)) {
      throw StateError('Auth plugin "$id" is already registered.');
    }

    final contributed = plugin is AuthEndpointContributor<TContext>
        ? (plugin as AuthEndpointContributor<TContext>).endpoints.toList(
            growable: false,
          )
        : <AuthEndpointDescriptor<TContext>>[];
    final contributedIds = <String>{};
    final contributedKeys = <String>{};
    for (final endpoint in contributed) {
      final endpointId = endpoint.id.trim();
      final path = _normalizeEndpointPath(endpoint.path);
      if (endpointId.isEmpty || path.isEmpty) {
        throw ArgumentError('Plugin "$id" contributed an invalid endpoint.');
      }
      if (_endpoints.containsKey(endpointId) ||
          !contributedIds.add(endpointId)) {
        throw StateError('Auth endpoint "$endpointId" is already registered.');
      }
      final key = '${endpoint.method.name}:$path';
      if (_endpointKeys.contains(key) || !contributedKeys.add(key)) {
        throw StateError('Auth endpoint path "$key" is already registered.');
      }
    }

    _plugins[id] = plugin;
    plugin.configure(
      AuthServerPluginContext<TContext>(
        store: _store,
        passwordHasher: _passwordHasher,
        passwordPolicy: _passwordPolicy,
        sessionStrategy: _sessionStrategy,
      ),
    );
    for (final endpoint in contributed) {
      _endpoints[endpoint.id.trim()] = endpoint;
      _endpointKeys.add(
        '${endpoint.method.name}:${_normalizeEndpointPath(endpoint.path)}',
      );
    }
  }

  void freeze() {
    if (_frozen) return;
    final topology = List<AuthServerPlugin<TContext>>.unmodifiable(
      _plugins.values,
    );
    for (final plugin
        in topology.whereType<AuthServerPluginTopologyAware<TContext>>()) {
      plugin.composePluginTopology(topology);
    }
    _frozen = true;
  }

  AuthServerPlugin<TContext>? find(String id) => _plugins[id.trim()];

  bool contains(String id) => find(id) != null;

  Iterable<AuthServerPlugin<TContext>> get values =>
      List<AuthServerPlugin<TContext>>.unmodifiable(_plugins.values);

  Iterable<AuthEndpointDescriptor<TContext>> get endpoints =>
      List<AuthEndpointDescriptor<TContext>>.unmodifiable(_endpoints.values);

  Future<void> enforceAuthenticationPolicy(
    AuthAuthenticationPolicyRequest<TContext> request,
  ) async {
    for (final plugin
        in _plugins.values
            .whereType<AuthAuthenticationPolicyContributor<TContext>>()) {
      await plugin.enforceAuthenticationPolicy(request);
    }
  }

  Iterable<AuthPersistenceSchema> get persistenceSchemas =>
      List<AuthPersistenceSchema>.unmodifiable(
        _plugins.values.whereType<AuthPersistenceContributor>().expand(
          (plugin) => plugin.persistenceSchemas,
        ),
      );

  Iterable<AuthClientOperationDescriptor> get clientOperations =>
      List<AuthClientOperationDescriptor>.unmodifiable(
        _plugins.values
            .whereType<AuthClientOperationContributor>()
            .expand((plugin) => plugin.clientOperations)
            .where((operation) => !operation.serverOnly),
      );

  Iterable<AuthRateLimitOperation> get rateLimitOperations =>
      List<AuthRateLimitOperation>.unmodifiable(
        _plugins.values.whereType<AuthRateLimitContributor>().expand(
          (plugin) => plugin.rateLimitOperations,
        ),
      );
}

String _normalizeEndpointPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return '/${trimmed.replaceAll(RegExp(r'^/+|/+$'), '')}';
}
