import 'package:routed_core/routed_core.dart';

import 'package:routed_http/src/binding/binding.dart';

/// Extension methods for binding data to models within the EngineContext.
extension BindingMethods on EngineContext {
  /// Binds the provided [model] using JSON binding.
  ///
  /// This method will attempt to bind the [model] using the [jsonBinding].
  /// It is an asynchronous operation.
  /// Binds the provided [model] using JSON binding.
  ///
  /// This method will attempt to bind the [model] using the [jsonBinding].
  /// It is an asynchronous operation.
  Future<T> bindJSON<T>(T model) {
    return shouldBindWith(model, jsonBinding);
  }

  /// Ensures that the provided [model] is bound using the specified [binding].
  ///
  /// This method will attempt to bind the [model] using the provided [binding].
  /// If the binding fails, it will abort the request with a forbidden status.
  Future<T> mustBindWith<T>(T model, Binding binding) async {
    try {
      return await shouldBindWith(model, binding);
    } on Object catch (_) {
      abortWithError(HttpStatus.forbidden);
      throw StateError('Binding failed'); // Should be unreachable due to abort
    }
  }

  /// Attempts to bind the provided [model] using the specified [binding].
  ///
  /// This method will use the [binding] to bind the [model] to the context.
  /// It returns the result of the binding operation.
  Future<T> shouldBindWith<T>(T model, Binding binding) {
    return binding.bind(this, model);
  }

  /// Binds [model] using the default binding for the request method and type.
  ///
  /// The binding is selected from the request method and content type.
  Future<T> bind<T>(T model) {
    return defaultBinding(
      request.method,
      request.contentType?.value ?? '',
    ).bind(this, model);
  }

  /// Binds the provided [model] using URI binding.
  ///
  /// This method will attempt to bind the [model] using the [uriBinding].
  /// It is an asynchronous operation.
  Future<T> bindQuery<T>(T model) {
    return shouldBindWith(model, uriBinding);
  }

  /// Attempts to bind [model] using the default request binding.
  ///
  /// The binding is selected from the request method and content type.
  Future<T> shouldBind<T>(T model) {
    final b = defaultBinding(request.method, request.contentType?.value ?? '');
    return b.bind(this, model);
  }
}
