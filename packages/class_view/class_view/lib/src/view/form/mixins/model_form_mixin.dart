import 'dart:async';

/// Mixin that provides model form functionality
mixin ModelFormMixin<T, U> {
  /// Fields to include in the form
  List<String> get fields => const [];

  /// Fields to exclude from the form
  List<String> get exclude => const [];

  /// Get the model instance
  Future<T?> getObject(U context) {
    throw UnimplementedError('getObject not implemented');
  }

  /// Save the model instance
  Future<T> saveObject(T object, Map<String, dynamic> data, U context) {
    throw UnimplementedError('saveObject not implemented');
  }

  /// Delete the model instance
  Future<void> deleteObject(T object, U context) {
    throw UnimplementedError('deleteObject not implemented');
  }

  /// Get form data from model
  Future<Map<String, dynamic>> getFormDataFromModel(T object) async {
    // Implementation would depend on your model system
    return {};
  }

  /// Update model from form data
  Future<void> updateModelFromForm(
    T object,
    Map<String, dynamic> data,
    U context,
  ) async {
    throw UnimplementedError('updateModelFromForm not implemented');
  }
}
