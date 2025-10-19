import 'dart:convert';

import 'renderable_mixin.dart';

/// Mixin that adds rendering capabilities to error collections
mixin RenderableErrorMixin on RenderableMixin {
  String get templateNameText;

  String get templateNameUl;

  String asJson({bool escapeHtml = false}) {
    return json.encode(getJsonData(escapeHtml: escapeHtml));
  }

  /// Render errors as plain text
  Future<String> asText() {
    return render(templateName: templateNameText);
  }

  /// Render errors as an unordered list
  Future<String> asUl() {
    return render(templateName: templateNameUl);
  }

  /// Get the data in JSON format
  Map<String, dynamic> getJsonData({bool escapeHtml = false});
}
