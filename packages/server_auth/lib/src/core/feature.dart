import 'dart:async';

import 'models.dart';
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
  });

  final TContext context;
  final AuthUser? user;
  final bool emailVerified;
  final String? activeOrganizationId;
  final String? activeTeamId;
  final FutureOr<void> Function(String? organizationId, String? teamId)?
  writeActiveSelection;
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

class AuthFeatureContext<TContext> {
  const AuthFeatureContext({required this.store});

  final AuthStore store;
}

abstract interface class AuthFeature<TContext> {
  String get id;

  void configure(AuthFeatureContext<TContext> context);
}

class AuthFeatureRegistry<TContext> {
  AuthFeatureRegistry({required AuthStore store}) : _store = store;

  final AuthStore _store;
  final Map<String, AuthFeature<TContext>> _features =
      <String, AuthFeature<TContext>>{};
  final Map<String, AuthEndpointDescriptor<TContext>> _endpoints =
      <String, AuthEndpointDescriptor<TContext>>{};
  final Set<String> _endpointKeys = <String>{};
  bool _frozen = false;

  bool get isFrozen => _frozen;

  void register(AuthFeature<TContext> feature) {
    if (_frozen) throw StateError('Auth feature topology is frozen.');
    final id = feature.id.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(feature.id, 'feature.id', 'must not be empty');
    }
    if (_features.containsKey(id)) {
      throw StateError('Auth feature "$id" is already registered.');
    }

    final contributed = feature is AuthEndpointContributor<TContext>
        ? (feature as AuthEndpointContributor<TContext>).endpoints.toList(
            growable: false,
          )
        : <AuthEndpointDescriptor<TContext>>[];
    final contributedIds = <String>{};
    final contributedKeys = <String>{};
    for (final endpoint in contributed) {
      final endpointId = endpoint.id.trim();
      final path = _normalizeEndpointPath(endpoint.path);
      if (endpointId.isEmpty || path.isEmpty) {
        throw ArgumentError('Feature "$id" contributed an invalid endpoint.');
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

    _features[id] = feature;
    feature.configure(AuthFeatureContext<TContext>(store: _store));
    for (final endpoint in contributed) {
      _endpoints[endpoint.id.trim()] = endpoint;
      _endpointKeys.add(
        '${endpoint.method.name}:${_normalizeEndpointPath(endpoint.path)}',
      );
    }
  }

  void freeze() => _frozen = true;

  AuthFeature<TContext>? find(String id) => _features[id.trim()];

  bool contains(String id) => find(id) != null;

  Iterable<AuthFeature<TContext>> get values =>
      List<AuthFeature<TContext>>.unmodifiable(_features.values);

  Iterable<AuthEndpointDescriptor<TContext>> get endpoints =>
      List<AuthEndpointDescriptor<TContext>>.unmodifiable(_endpoints.values);

  Iterable<AuthPersistenceSchema> get persistenceSchemas =>
      List<AuthPersistenceSchema>.unmodifiable(
        _features.values.whereType<AuthPersistenceContributor>().expand(
          (feature) => feature.persistenceSchemas,
        ),
      );

  Iterable<AuthClientOperationDescriptor> get clientOperations =>
      List<AuthClientOperationDescriptor>.unmodifiable(
        _features.values
            .whereType<AuthClientOperationContributor>()
            .expand((feature) => feature.clientOperations)
            .where((operation) => !operation.serverOnly),
      );

  Iterable<AuthRateLimitOperation> get rateLimitOperations =>
      List<AuthRateLimitOperation>.unmodifiable(
        _features.values.whereType<AuthRateLimitContributor>().expand(
          (feature) => feature.rateLimitOperations,
        ),
      );
}

String _normalizeEndpointPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return '/${trimmed.replaceAll(RegExp(r'^/+|/+$'), '')}';
}
