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
