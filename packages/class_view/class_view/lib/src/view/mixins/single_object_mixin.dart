import 'dart:async';

import '../exceptions/http.dart';
import 'context_mixin.dart';

/// Mixin that provides functionality for working with a single object
mixin SingleObjectMixin<T> on ContextMixin {
  /// Model class that this view operates on
  Type get model => T;

  /// The name of the URL parameter containing the object lookup key
  String get lookupParam => 'id';

  /// Name of the context variable to use for the object
  String? get contextObjectName => null;

  /// Get the object this view is displaying
  Future<T?> getObject() async {
    throw UnimplementedError('Subclasses must implement getObject()');
  }

  /// Get the object or return a 404 response
  Future<T> getObjectOr404() async {
    final object = await getObject();
    if (object == null) {
      throw HttpException.notFound('Object not found');
    }
    return object;
  }

  /// Get the context variable name for the object
  String getContextObjectName() {
    if (contextObjectName != null) {
      return contextObjectName!;
    }
    // Default to lowercase class name
    return T.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Add the object to the context data
  @override
  Future<Map<String, dynamic>> getContextData() async {
    final baseContext = await super.getContextData();
    final object = await getObjectOr404();
    print('SingleObjectMixin.getContextData() - baseContext: $baseContext');
    print('SingleObjectMixin.getContextData() - object: $object');
    final context = {...baseContext, getContextObjectName(): object};
    print('SingleObjectMixin.getContextData() - final context: $context');
    return context;
  }

  @override
  Future<void> get() async {
    final contextData = await getContextData();
    await sendJson(contextData);
  }
}
