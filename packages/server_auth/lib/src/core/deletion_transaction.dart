import 'dart:async';

import 'models.dart';

/// Opaque identity for one persistence/transaction domain.
///
/// A plan is valid only for the exact domain instance that created it. Domain
/// implementations are owned by storage adapters; application code must not
/// manufacture a domain and assume that it is interchangeable with another
/// adapter instance.
abstract interface class AuthUserDeletionDomain {}

/// The domain owned by [InMemoryAuthStore].
///
/// This type is public so in-memory plugin stores can construct typed plans,
/// but identity rather than type is what authorizes a plan for execution.
final class AuthInMemoryUserDeletionDomain implements AuthUserDeletionDomain {
  AuthInMemoryUserDeletionDomain();
}

/// An immutable description of one plugin-owned user-data deletion.
///
/// Plans contain typed backend operations, never arbitrary mutation callbacks.
/// Storage coordinators validate the complete set of plans before executing
/// any operation.
abstract interface class AuthUserDeletionPlan {
  String get userId;

  String get namespace;

  AuthUserDeletionDomain get domain;
}

/// Domain-bound namespace marker for plugins whose user state is stored wholly
/// inside core persistence and therefore needs no additional mutation.
final class AuthNoopUserDeletionPlan implements AuthUserDeletionPlan {
  AuthNoopUserDeletionPlan({
    required this.domain,
    required String userId,
    required String namespace,
  }) : userId = _normalizeUserId(userId),
       namespace = _normalizeNamespace(namespace);

  @override
  final AuthUserDeletionDomain domain;

  @override
  final String userId;

  @override
  final String namespace;
}

/// A typed reversible operation used by the in-memory coordinator.
///
/// Implementations are storage operations bound to one store and one user.
/// They are intentionally carried by [AuthInMemoryUserDeletionPlan] rather
/// than exposed as store-level delete/checkpoint compatibility methods.
abstract interface class AuthInMemoryUserDeletionOperation {
  Object captureState();

  FutureOr<void> apply();

  FutureOr<void> restoreState(Object state);
}

/// Reversible state owned by an in-memory persistence store.
abstract interface class AuthInMemoryDeletionState {
  Object captureDeletionState();

  FutureOr<void> restoreDeletionState(Object state);
}

/// A user-scoped in-memory store operation used to build a deletion plan.
abstract interface class AuthInMemoryUserDeletionStore
    implements AuthInMemoryDeletionState {
  FutureOr<void> deleteUserDataForDeletion(String userId);
}

/// Core in-memory persistence owned by one deletion coordinator.
///
/// The coordinator depends on this typed backend contract instead of accepting
/// mutation callbacks. Implementations must include the deletion token and all
/// core user-owned records in [captureDeletionState].
abstract interface class AuthInMemoryUserDeletionBackend
    implements AuthInMemoryDeletionState {
  FutureOr<AuthUser?> findUserForDeletion(String userId);

  FutureOr<void> validateUserDeletion(String userId);

  FutureOr<bool> consumeUserDeletionToken(String userId, String token);

  FutureOr<bool> deleteCoreUserData(String userId);
}

/// Adapts one typed in-memory store into an immutable plan operation.
final class AuthInMemoryStoreDeletionOperation
    implements AuthInMemoryUserDeletionOperation {
  AuthInMemoryStoreDeletionOperation({
    required AuthInMemoryUserDeletionStore store,
    required String userId,
  }) : _store = store,
       _userId = _normalizeUserId(userId);

  final AuthInMemoryUserDeletionStore _store;
  final String _userId;

  @override
  Object captureState() => _store.captureDeletionState();

  @override
  FutureOr<void> apply() => _store.deleteUserDataForDeletion(_userId);

  @override
  FutureOr<void> restoreState(Object state) =>
      _store.restoreDeletionState(state);
}

/// Composes multiple typed in-memory operations owned by one plugin.
final class AuthInMemoryCompositeDeletionOperation
    implements AuthInMemoryUserDeletionOperation {
  AuthInMemoryCompositeDeletionOperation(
    Iterable<AuthInMemoryUserDeletionOperation> operations,
  ) : _operations = List<AuthInMemoryUserDeletionOperation>.unmodifiable(
        operations,
      ) {
    if (_operations.isEmpty) {
      throw ArgumentError.value(
        operations,
        'operations',
        'must contain at least one operation',
      );
    }
  }

  final List<AuthInMemoryUserDeletionOperation> _operations;

  @override
  List<Object> captureState() => List<Object>.unmodifiable([
    for (final operation in _operations) operation.captureState(),
  ]);

  @override
  Future<void> apply() async {
    for (final operation in _operations) {
      await operation.apply();
    }
  }

  @override
  Future<void> restoreState(Object state) async {
    final values = state as List<Object>;
    for (var index = values.length - 1; index >= 0; index--) {
      await _operations[index].restoreState(values[index]);
    }
  }
}

/// Immutable, in-memory deletion plan.
final class AuthInMemoryUserDeletionPlan implements AuthUserDeletionPlan {
  AuthInMemoryUserDeletionPlan({
    required AuthInMemoryUserDeletionDomain domain,
    required String userId,
    required String namespace,
    required AuthInMemoryUserDeletionOperation operation,
  }) : _domain = domain,
       _userId = _normalizeUserId(userId),
       _namespace = _normalizeNamespace(namespace),
       _operation = operation;

  final AuthInMemoryUserDeletionDomain _domain;
  final String _userId;
  final String _namespace;
  final AuthInMemoryUserDeletionOperation _operation;

  @override
  AuthInMemoryUserDeletionDomain get domain => _domain;

  @override
  String get userId => _userId;

  @override
  String get namespace => _namespace;
}

/// A contributor that creates exactly one immutable plan for its namespace.
abstract interface class AuthUserDeletionPlanContributor {
  String get userDataNamespace;

  FutureOr<AuthUserDeletionPlan> createUserDeletionPlan(AuthUser user);
}

/// Backend-specific plugin store that can build its own immutable plan.
///
/// This keeps SQL and other durable transaction primitives in their adapter
/// package while allowing a framework-agnostic plugin to request a plan.
abstract interface class AuthUserDeletionPlanFactory {
  FutureOr<AuthUserDeletionPlan> createDeletionPlan({
    required AuthUserDeletionDomain domain,
    required AuthUser user,
    required String namespace,
  });
}

/// A store that owns a deletion domain and coordinates its configured plans.
///
/// Active contributors are not a durable inventory of data written by plugins
/// that were enabled in an earlier deployment. A durable host must therefore
/// either enumerate and require every historical external namespace before
/// deletion, or fail closed. Backend-owned optional substores should be
/// cleaned unconditionally, and a hard-deletion receipt should prevent an
/// omitted external credential from becoming active through user-ID reuse.
/// `server_auth` cannot discover a removed third-party store on its own.
abstract interface class AuthUserDeletionCoordinatorHost {
  AuthUserDeletionCoordinator get userDeletionCoordinator;

  /// Freezes the complete plugin-owned deletion topology.
  ///
  /// A host accepts this binding exactly once. Deletion fails closed until the
  /// topology has been bound, including when the iterable is empty.
  void bindUserDeletionPlanContributors(
    Iterable<AuthUserDeletionPlanContributor> contributors,
  );
}

/// Backend-owned coordinator for hard user deletion.
abstract interface class AuthUserDeletionCoordinator {
  AuthUserDeletionDomain get domain;

  Set<String> get requiredUserDeletionNamespaces;

  Future<List<AuthUserDeletionPlan>> plansForUser(AuthUser user);

  Future<bool> deleteUser(
    String userId, {
    Iterable<AuthUserDeletionPlan>? plans,
  });

  Future<bool> confirmAndDeleteUser({
    required String userId,
    required String token,
    Iterable<AuthUserDeletionPlan>? plans,
    DateTime? now,
  });
}

/// A conformance-friendly fault point for coordinator implementations.
enum AuthUserDeletionFaultPoint { beforeMutation, plugin, core, restore }

/// Thrown when a deletion plan set cannot describe one complete transaction.
final class AuthUserDeletionPreflightException implements Exception {
  const AuthUserDeletionPreflightException(this.message);

  final String message;

  @override
  String toString() => 'AuthUserDeletionPreflightException: $message';
}

/// Shared validation for backend coordinators.
///
/// The backend-specific coordinator supplies the supported plan type and exact
/// domain check. This helper deliberately performs no storage mutation.
final class AuthUserDeletionPreflight {
  const AuthUserDeletionPreflight._();

  static List<AuthUserDeletionPlan> validate({
    required String userId,
    required Iterable<AuthUserDeletionPlan> plans,
    required Set<String> requiredNamespaces,
    required AuthUserDeletionDomain domain,
    required bool Function(AuthUserDeletionPlan plan) isSupported,
  }) {
    final normalizedUserId = _normalizeUserId(userId);
    final values = plans.toList(growable: false);
    final namespaces = <String>{};
    for (final plan in values) {
      if (!isSupported(plan)) {
        throw AuthUserDeletionPreflightException(
          'Unsupported deletion plan type: ${plan.runtimeType}.',
        );
      }
      if (plan.userId != normalizedUserId) {
        throw AuthUserDeletionPreflightException(
          'Deletion plan user does not match the requested user.',
        );
      }
      if (!identical(plan.domain, domain)) {
        throw AuthUserDeletionPreflightException(
          'Deletion plan belongs to a foreign persistence domain.',
        );
      }
      final namespace = _normalizeNamespace(plan.namespace);
      if (namespace != plan.namespace || !namespaces.add(namespace)) {
        throw AuthUserDeletionPreflightException(
          'Deletion plan namespaces must be unique and normalized.',
        );
      }
    }
    if (!namespaces.containsAll(requiredNamespaces)) {
      final missing = requiredNamespaces.difference(namespaces);
      throw AuthUserDeletionPreflightException(
        'Deletion plans are missing required namespaces: ${missing.join(', ')}.',
      );
    }
    if (namespaces.length != requiredNamespaces.length) {
      final unexpected = namespaces.difference(requiredNamespaces);
      if (unexpected.isNotEmpty) {
        throw AuthUserDeletionPreflightException(
          'Deletion plans contain unknown namespaces: ${unexpected.join(', ')}.',
        );
      }
    }
    return values;
  }
}

/// Coordinator implementation for process-local in-memory stores.
final class AuthInMemoryUserDeletionCoordinator
    implements AuthUserDeletionCoordinator {
  AuthInMemoryUserDeletionCoordinator({
    required this.domain,
    required AuthInMemoryUserDeletionBackend backend,
  }) : _backend = backend;

  @override
  final AuthInMemoryUserDeletionDomain domain;

  final AuthInMemoryUserDeletionBackend _backend;
  List<AuthUserDeletionPlanContributor> _contributors = const [];
  bool _bound = false;
  Future<void> _tail = Future<void>.value();

  @override
  Set<String> get requiredUserDeletionNamespaces => {
    for (final contributor in _contributors)
      _normalizeNamespace(contributor.userDataNamespace),
  };

  void bind(Iterable<AuthUserDeletionPlanContributor> contributors) {
    if (_bound) {
      throw StateError('Auth deletion contributors are already bound.');
    }
    final values = contributors.toList(growable: false);
    final namespaces = <String>{};
    for (final contributor in values) {
      final namespace = _normalizeNamespace(contributor.userDataNamespace);
      if (namespace != contributor.userDataNamespace ||
          !namespaces.add(namespace)) {
        throw StateError(
          'Auth deletion contributor namespaces must be unique and normalized.',
        );
      }
    }
    _contributors = List<AuthUserDeletionPlanContributor>.unmodifiable(values);
    _bound = true;
  }

  @override
  Future<List<AuthUserDeletionPlan>> plansForUser(AuthUser user) async {
    _ensureBound();
    final plans = <AuthUserDeletionPlan>[];
    for (final contributor in _contributors) {
      plans.add(await contributor.createUserDeletionPlan(user));
    }
    return List<AuthUserDeletionPlan>.unmodifiable(plans);
  }

  @override
  Future<bool> deleteUser(
    String userId, {
    Iterable<AuthUserDeletionPlan>? plans,
  }) => _serialize(
    () => _deleteUserSerialized(
      userId: userId,
      plans: plans,
      consumeToken: false,
    ),
  );

  @override
  Future<bool> confirmAndDeleteUser({
    required String userId,
    required String token,
    Iterable<AuthUserDeletionPlan>? plans,
    DateTime? now,
  }) => _serialize(
    () => _confirmAndDeleteUserSerialized(
      userId: userId,
      token: token,
      plans: plans,
      now: now,
    ),
  );

  Future<T> _serialize<T>(Future<T> Function() operation) async {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<bool> _deleteUserSerialized({
    required String userId,
    required Iterable<AuthUserDeletionPlan>? plans,
    required bool consumeToken,
    String? token,
  }) async {
    final normalizedUserId = _normalizeUserId(userId);
    _ensureBound();
    final user = await _backend.findUserForDeletion(normalizedUserId);
    if (user == null) return false;
    await _backend.validateUserDeletion(normalizedUserId);
    final validated = AuthUserDeletionPreflight.validate(
      userId: normalizedUserId,
      plans: plans ?? await plansForUser(user),
      requiredNamespaces: requiredUserDeletionNamespaces,
      domain: domain,
      isSupported: (plan) =>
          plan is AuthInMemoryUserDeletionPlan ||
          plan is AuthNoopUserDeletionPlan,
    );
    final operations = <AuthInMemoryUserDeletionOperation>[
      for (final plan in validated.whereType<AuthInMemoryUserDeletionPlan>())
        plan._operation,
    ];
    final coreState = _backend.captureDeletionState();
    final checkpoints = <Object>[
      for (final operation in operations) operation.captureState(),
    ];
    try {
      if (consumeToken &&
          (token == null ||
              !await _backend.consumeUserDeletionToken(
                normalizedUserId,
                token,
              ))) {
        return false;
      }
      for (final operation in operations) {
        await operation.apply();
      }
      final deleted = await _backend.deleteCoreUserData(normalizedUserId);
      if (!deleted) throw StateError('Core user deletion failed.');
      return true;
    } catch (error, stackTrace) {
      try {
        for (var index = operations.length - 1; index >= 0; index--) {
          await operations[index].restoreState(checkpoints[index]);
        }
        await _backend.restoreDeletionState(coreState);
      } catch (restoreError, restoreStackTrace) {
        Error.throwWithStackTrace(
          StateError('In-memory deletion rollback failed: $restoreError'),
          restoreStackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<bool> _confirmAndDeleteUserSerialized({
    required String userId,
    required String token,
    required Iterable<AuthUserDeletionPlan>? plans,
    required DateTime? now,
  }) async {
    final normalizedUserId = _normalizeUserId(userId);
    if (token.trim().isEmpty) return false;
    final user = await _backend.findUserForDeletion(normalizedUserId);
    if (user == null) return false;
    final deletionPlans = plans ?? await plansForUser(user);
    // Token validation/consumption is serialized with the complete operation.
    // If any later operation fails, the core operation restores the token via
    // the store-owned core snapshot.
    return _deleteUserSerialized(
      userId: normalizedUserId,
      plans: deletionPlans,
      consumeToken: true,
      token: token,
    );
  }

  void _ensureBound() {
    if (!_bound) {
      throw StateError('Auth deletion contributor topology is not bound.');
    }
  }
}

String _normalizeUserId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, 'userId', 'must not be empty');
  }
  return normalized;
}

String _normalizeNamespace(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, 'namespace', 'must not be empty');
  }
  return normalized;
}
