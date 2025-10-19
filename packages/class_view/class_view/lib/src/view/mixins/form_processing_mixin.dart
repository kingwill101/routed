import 'dart:async';

import '../form/validation.dart' show ValidationError;
import 'view_mixin.dart';

/// Mixin that provides form processing functionality
mixin FormProcessingMixin on ViewMixin {
  /// Initial form data
  Map<String, dynamic> get initialData => {};

  /// Form validation rules
  Map<String, String> get validationRules => {};

  /// URL to redirect to after successful form processing
  String? get successUrl => null;

  /// Process form data
  Future<void> processForm(Map<String, dynamic> data) async {
    throw UnimplementedError('Subclasses must implement processForm');
  }

  /// Handle successful form submission
  Future<void> onSuccess() async {
    throw UnimplementedError('Subclasses must implement onSuccess');
  }

  /// Handle form validation errors
  Future<void> handleValidationError(ValidationError error) async {
    throw UnimplementedError('Subclasses must implement handleValidationError');
  }

  @override
  Future<void> handleError(Object error, [StackTrace? stackTrace]) async {
    throw UnimplementedError('Subclasses must implement handleError');
  }

  /// Get the form's initial data
  @override
  Future<Map<String, dynamic>> getFormData() async {
    return {...initialData};
  }
}
