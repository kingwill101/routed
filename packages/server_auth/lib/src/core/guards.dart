import 'dart:async';

/// Result for a guard evaluation.
class GuardResult<TResponse> {
  const GuardResult.allow() : allowed = true, response = null;

  const GuardResult.deny([this.response]) : allowed = false;

  final bool allowed;
  final TResponse? response;
}

/// Guard callback contract.
typedef AuthGuard<TContext, TResponse> =
    FutureOr<GuardResult<TResponse>> Function(TContext ctx);

/// Registry for guard callbacks keyed by name.
class AuthGuardRegistry<TContext, TResponse> {
  final Map<String, AuthGuard<TContext, TResponse>> _entries =
      <String, AuthGuard<TContext, TResponse>>{};

  /// Registers [handler] under [name].
  void register(
    String name,
    AuthGuard<TContext, TResponse> handler, {
    bool overrideExisting = true,
  }) {
    final key = name.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Registry key cannot be empty.');
    }
    if (_entries.containsKey(key) && !overrideExisting) {
      return;
    }
    _entries[key] = handler;
  }

  /// Unregisters [name].
  void unregister(String name) {
    _entries.remove(name.trim());
  }

  /// Resolves guard callback by [name].
  AuthGuard<TContext, TResponse>? resolve(String name) => _entries[name.trim()];

  /// Registered guard names.
  Iterable<String> get names => _entries.keys;
}

/// Framework-agnostic guard evaluation service.
class AuthGuardService<TContext, TResponse> {
  AuthGuardService({AuthGuardRegistry<TContext, TResponse>? registry})
    : registry = registry ?? AuthGuardRegistry<TContext, TResponse>();

  /// Backing registry for guard callbacks.
  final AuthGuardRegistry<TContext, TResponse> registry;

  void register(
    String name,
    AuthGuard<TContext, TResponse> handler, {
    bool overrideExisting = true,
  }) {
    registry.register(name, handler, overrideExisting: overrideExisting);
  }

  void unregister(String name) {
    registry.unregister(name);
  }

  /// Returns the first denied response across [guardNames], if any.
  ///
  /// When a guard denies without attaching a response, [onDenied] is used to
  /// materialize one.
  Future<TResponse?> firstDenied(
    Iterable<String> guardNames,
    TContext context, {
    TResponse Function(TContext context, String guardName)? onDenied,
  }) async {
    for (final name in guardNames) {
      final handler = registry.resolve(name);
      if (handler == null) {
        continue;
      }

      final result = await Future.sync(() => handler(context));
      if (!result.allowed) {
        return result.response ?? onDenied?.call(context, name);
      }
    }
    return null;
  }
}
