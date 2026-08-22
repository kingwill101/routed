// Binding abstraction for Routed HTTP per refactor.md §11.
// Public surface; EngineContext comes from public `routed` barrel.
import 'dart:async';

import 'package:routed_core/routed_core.dart';

import 'form.dart' show FormBinding;
import 'json.dart' show JsonBinding;
import 'multipart.dart' show MultipartBinding;
import 'query.dart' show QueryBinding;
import 'uri.dart' show UriBinding;
import 'xml.dart' show XmlBinding;

/// Interface for objects that can be bound from a map of data.
abstract class Bindable {
  void bind(Map<String, dynamic> data);
}

/// The `Binding` interface, analogous to Gin's "Binding".
abstract class Binding {
  String get name;
  MimeType? get mimeType;
  Future<T> bind<T>(EngineContext context, T instance);
}

final jsonBinding = JsonBinding();
final formBinding = FormBinding();
final uriBinding = UriBinding();
final multipartBinding = MultipartBinding();
final queryBinding = QueryBinding();
final xmlBinding = XmlBinding();

enum MimeType {
  json('application/json'),
  html('text/html'),
  xml('application/xml'),
  xml2('text/xml'),
  plain('text/plain'),
  postForm('application/x-www-form-urlencoded'),
  multipartPostForm('multipart/form-data'),
  protobuf('application/x-protobuf'),
  msgpack('application/x-msgpack'),
  msgpack2('application/msgpack'),
  yaml('application/x-yaml'),
  yaml2('application/yaml'),
  toml('application/toml'),
  unknown('unknown');

  final String value;
  const MimeType(this.value);
}

Binding defaultBinding(String method, String contentType) {
  if (method.toUpperCase() == 'GET') {
    return QueryBinding();
  }
  final mime =
      MimeType.values.where((m) => m.value == contentType).firstOrNull ?? '';
  switch (mime) {
    case MimeType.json:
      return jsonBinding;
    case MimeType.xml:
    case MimeType.xml2:
      return xmlBinding;
    case MimeType.multipartPostForm:
      return multipartBinding;
    case MimeType.postForm:
      return formBinding;
    default:
      return formBinding;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
