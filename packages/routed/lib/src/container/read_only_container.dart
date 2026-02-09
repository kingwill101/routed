import 'container.dart';

/// Read-only view of a [Container] that prevents mutations.
class ReadOnlyContainer extends Container {
  ReadOnlyContainer(this._inner);

  final Container _inner;

  Never _throwMutation(String method) {
    throw StateError(
      'Container mutation is not allowed in fast-path mode: $method',
    );
  }

  @override
  void bind<T>(
    Future<T> Function(Container) factory, {
    bool singleton = false,
  }) {
    _throwMutation('bind');
  }

  @override
  void singleton<T>(Future<T> Function(Container) factory) {
    _throwMutation('singleton');
  }

  @override
  void scoped<T>(Future<T> Function(Container) factory) {
    _throwMutation('scoped');
  }

  @override
  void clearScoped() {
    _throwMutation('clearScoped');
  }

  @override
  void instance<T>(T instance) {
    _throwMutation('instance');
  }

  @override
  void remove<T>() {
    _throwMutation('remove');
  }

  @override
  void addContextualBinding(
    Type concrete,
    Type abstract,
    dynamic implementation,
  ) {
    _throwMutation('addContextualBinding');
  }

  @override
  void resolving<T>(void Function(T instance, Container container) callback) {
    _throwMutation('resolving');
  }

  @override
  void afterResolving<T>(
    void Function(T instance, Container container) callback,
  ) {
    _throwMutation('afterResolving');
  }

  @override
  void alias<T, U>() {
    _throwMutation('alias');
  }

  @override
  Future<T> make<T>() => _inner.make<T>();

    @override
    Future<void> waitFor<T>({Duration? timeout}) =>
      _inner.waitFor<T>(timeout: timeout);

    @override
    Future<void> waitForType(Type type, {Duration? timeout}) =>
      _inner.waitForType(type, timeout: timeout);

    @override
    Future<T> makeWhenAvailable<T>({Duration? timeout}) =>
      _inner.makeWhenAvailable<T>(timeout: timeout);

  @override
  Future<List<dynamic>> makeAll(List<Type> types) => _inner.makeAll(types);

  @override
  T get<T>() => _inner.get<T>();

  @override
  bool has<T>() => _inner.has<T>();

  @override
  Container createChild() {
    _throwMutation('createChild');
  }

  @override
  Future<void> cleanup() async {
    // No-op for read-only container - nothing to clean up
    // The underlying container is shared and should not be cleaned up per-request
  }
}
