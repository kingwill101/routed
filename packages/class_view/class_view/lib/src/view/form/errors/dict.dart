import 'dart:convert';

import '../mixins/renderable_error_mixin.dart';
import '../mixins/renderable_mixin.dart';
import '../renderer.dart';
import '../validation.dart' show ValidationError;
import '../../form/errors/list.dart';

/// A collection of errors that knows how to display itself in various formats.
/// The dictionary keys are the field names, and the values are the errors.
class ErrorDict with RenderableMixin, RenderableErrorMixin {
  final Map<String, ErrorList> _errors = {};

  @override
  final Renderer? renderer;

  @override
  String get templateName => 'form/errors/dict/default.html';

  @override
  String get templateNameText => 'form/errors/dict/text.txt';

  @override
  String get templateNameUl => 'form/errors/dict/ul.html';

  ErrorDict({this.renderer});

  /// Get the raw error data
  Map<String, List<ValidationError>> asData() {
    return Map.fromEntries(
      _errors.entries.map((e) => MapEntry(e.key, e.value.asData())),
    );
  }

  @override
  Map<String, dynamic> getJsonData({bool escapeHtml = false}) {
    return Map.fromEntries(
      _errors.entries.map(
        (e) => MapEntry(e.key, e.value.getJsonData(escapeHtml: escapeHtml)),
      ),
    );
  }

  /// Convert errors to JSON format
  @override
  String asJson({bool escapeHtml = false}) {
    return json.encode(getJsonData(escapeHtml: escapeHtml));
  }

  @override
  Map<String, dynamic> getContext() {
    return {'errors': _errors.entries.toList(), 'error_class': 'errorlist'};
  }

  // Map interface implementation
  void operator []=(String key, ErrorList value) => _errors[key] = value;

  ErrorList? operator [](String key) => _errors[key];

  void clear() => _errors.clear();

  Iterable<MapEntry<String, ErrorList>> get entries => _errors.entries;

  void addAll(Map<String, ErrorList> other) => _errors.addAll(other);

  bool containsKey(String key) => _errors.containsKey(key);

  Iterable<String> get keys => _errors.keys;

  Iterable<ErrorList> get values => _errors.values;

  bool get isEmpty => _errors.isEmpty;

  bool get isNotEmpty => _errors.isNotEmpty;

  int get length => _errors.length;
}
