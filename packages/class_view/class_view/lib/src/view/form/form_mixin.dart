import 'dart:async';
import 'dart:io' show HttpStatus;

import '../mixins/success_url_mixin.dart';
import '../mixins/view_mixin.dart';
import 'validation.dart';

/// Mixin that provides form processing functionality
mixin FormMixin on ViewMixin, SuccessFailureUrlMixin {
  /// The form class to use
  Type get formClass;

  /// Get initial form data
  Future<Map<String, dynamic>> getInitialData() async {
    return {};
  }

  /// Validate form data
  Future<bool> validateForm(Map<String, dynamic> data) async {
    return true;
  }

  /// Process valid form data
  Future<void> processValidForm(Map<String, dynamic> data) async {}

  /// Handle form success
  Future<void> formSuccess() async {
    if (successUrl != null) {
      redirect(successUrl!);
    }
  }

  /// Handle form failure
  Future<void> formFailure(dynamic error) async {
    if (error is ValidationError) {
      sendJson({'errors': error.message}, statusCode: HttpStatus.badRequest);
    } else {
      sendJson({
        'error': error.toString(),
      }, statusCode: HttpStatus.internalServerError);
    }
  }
}
