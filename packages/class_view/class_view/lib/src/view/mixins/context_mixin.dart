import 'dart:async';

import 'view_mixin.dart';

/// Mixin that provides context data functionality similar to Django's ContextMixin
mixin ContextMixin on ViewMixin {
  /// Extra context data to include in the template context
  Map<String, dynamic> get extraContext => {};

  /// Get extra context data to be included in the template context
  Future<Map<String, dynamic>> getExtraContext() async {
    return extraContext;
  }

  /// Get the base context data
  Future<Map<String, dynamic>> getContextData() async {
    final contextData = {...await getExtraContext()};
    return contextData;
  }
}
