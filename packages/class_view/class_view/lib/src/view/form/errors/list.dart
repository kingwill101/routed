import 'dart:convert';

import '../mixins/renderable_error_mixin.dart';
import '../mixins/renderable_mixin.dart';
import '../renderer.dart';
import '../validation.dart' show ValidationError;

/// A collection of errors that knows how to display itself in various formats.
class ErrorList with RenderableMixin, RenderableErrorMixin {
  final List<ValidationError> _errors = [];
  final String errorClass;
  @override
  final Renderer? renderer;
  final String? fieldId;

  @override
  String get templateName => 'form/errors/list/default.html';

  @override
  String get templateNameText => 'form/errors/list/text.txt';

  @override
  String get templateNameUl => 'form/errors/list/ul.html';

  ErrorList({
    List<ValidationError>? initList,
    String? errorClass,
    this.renderer,
    this.fieldId,
  }) : errorClass = errorClass != null ? 'errorlist $errorClass' : 'errorlist' {
    if (initList != null) {
      _errors.addAll(initList);
    }
  }

  List<ValidationError> asData() {
    return List.from(_errors);
  }

  ErrorList copy() {
    return ErrorList(
      initList: List.from(_errors),
      errorClass: errorClass,
      renderer: renderer,
      fieldId: fieldId,
    );
  }

  @override
  Map<String, dynamic> getJsonData({bool escapeHtml = false}) {
    return {
      'errors': _errors.map((ValidationError error) {
        final message = error.message;
        return {
          'message': escapeHtml ? htmlEscape.convert(message) : message,
          'code': error,
        };
      }).toList(),
    };
  }

  @override
  Map<String, dynamic> getContext() {
    return {'errors': _errors, 'error_class': errorClass, 'id': fieldId};
  }

  // List interface implementation
  void add(ValidationError error) => _errors.add(error);

  void addAll(Iterable<ValidationError> errors) => _errors.addAll(errors);

  ValidationError operator [](int index) => _errors[index];

  void operator []=(int index, ValidationError value) => _errors[index] = value;

  int get length => _errors.length;

  bool get isEmpty => _errors.isEmpty;

  bool get isNotEmpty => _errors.isNotEmpty;

  void clear() => _errors.clear();

  Iterable<ValidationError> get iterator => _errors;

  bool contains(Object? element) => _errors.contains(element);
}
