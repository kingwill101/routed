part of 'context.dart';

/// Extension methods for binding data to models within the EngineContext.
extension BindingMethods on EngineContext {
  /// Binds the provided [model] using JSON binding.
  ///
  /// This method will attempt to bind the [model] using the [jsonBinding].
  /// It is an asynchronous operation.
  Future<void> bindJSON(dynamic model) async {
    await shouldBindWith(model, jsonBinding);
  }

  /// Ensures that the provided [model] is bound using the specified [binding].
  ///
  /// This method will attempt to bind the [model] using the provided [binding].
  /// If the binding fails, it will abort the request with a forbidden status.
  void mustBindWith(dynamic model, Binding binding) {
    try {
      shouldBindWith(model, binding);
    } catch (e) {
      abortWithError(HttpStatus.forbidden);
    }
  }

  /// Attempts to bind the provided [model] using the specified [binding].
  ///
  /// This method will use the [binding] to bind the [model] to the context.
  /// It returns the result of the binding operation.
  dynamic shouldBindWith(dynamic model, Binding binding) {
    return binding.bind(this, model);
  }

  /// Binds the provided [model] using the default binding for the request method and content type.
  ///
  /// This method will determine the appropriate binding based on the request method and content type,
  /// and then bind the [model] using that binding. It is an asynchronous operation.
  Future<void> bind(dynamic model) async {
    await defaultBinding(request.method, request.contentType?.value ?? '')
        .bind(this, model);
  }

  /// Binds the provided [model] using URI binding.
  ///
  /// This method will attempt to bind the [model] using the [uriBinding].
  /// It is an asynchronous operation.
  Future<void> bindQuery(dynamic model) async {
    await shouldBindWith(model, uriBinding);
  }

  /// Attempts to bind the provided [model] using the default binding for the request method and content type.
  ///
  /// This method will determine the appropriate binding based on the request method and content type,
  /// and then bind the [model] using that binding. It is an asynchronous operation.
  Future<void> shouldBind(dynamic model) async {
    final b = defaultBinding(request.method, request.contentType?.value ?? '');
    await b.bind(this, model);
  }

  /// Validates the provided [data] using the default binding for the request method and content type.
  ///
  /// This method will determine the appropriate binding based on the request method and content type,
  /// and then validate the [data] using that binding. It is an asynchronous operation.
  Future<void> validate(Map<String, String> data) async {
    await defaultBinding(request.method, request.contentType?.value ?? '')
        .validate(this, data);
  }
}
