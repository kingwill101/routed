/// Binding abstractions for decoding HTTP request data into application models.
library;

// Binding and model interfaces are intentionally abstract public extension
// points.
// ignore_for_file: one_member_abstracts
import 'dart:async';

import 'package:routed_core/routed_core.dart';

import 'package:routed_http/src/binding/form.dart' show FormBinding;
import 'package:routed_http/src/binding/json.dart' show JsonBinding;
import 'package:routed_http/src/binding/multipart.dart' show MultipartBinding;
import 'package:routed_http/src/binding/query.dart' show QueryBinding;
import 'package:routed_http/src/binding/uri.dart' show UriBinding;
import 'package:routed_http/src/binding/xml.dart' show XmlBinding;

/// Interface for objects that can be bound from a map of data.
abstract class Bindable {
  /// Applies decoded request data to this object.
  void bind(Map<String, dynamic> data);
}

/// Decodes request data and applies it to an application model.
abstract class Binding {
  /// The name used to identify this binding.
  String get name;

  /// The content type handled by this binding, or `null` for URI/query data.
  MimeType? get mimeType;

  /// Binds request data to [instance] and returns the same instance.
  Future<T> bind<T>(EngineContext context, T instance);
}

/// The built-in JSON request binding.
final jsonBinding = JsonBinding();

/// The built-in URL-encoded form binding.
final formBinding = FormBinding();

/// The built-in URI parameter binding.
final uriBinding = UriBinding();

/// The built-in multipart form binding.
final multipartBinding = MultipartBinding();

/// The built-in query parameter binding.
final queryBinding = QueryBinding();

/// The built-in XML request binding.
final xmlBinding = XmlBinding();

/// Common MIME types supported by the built-in request bindings.
enum MimeType {
  /// JSON request or response data.
  json('application/json'),

  /// HTML document data.
  html('text/html'),

  /// XML request or response data.
  xml('application/xml'),

  /// XML data using the `text/xml` media type.
  xml2('text/xml'),

  /// Plain text data.
  plain('text/plain'),

  /// URL-encoded form data.
  postForm('application/x-www-form-urlencoded'),

  /// Multipart form data.
  multipartPostForm('multipart/form-data'),

  /// Protocol Buffers data.
  protobuf('application/x-protobuf'),

  /// MessagePack data using the canonical media type.
  msgpack('application/x-msgpack'),

  /// MessagePack data using the alternate media type.
  msgpack2('application/msgpack'),

  /// YAML data using the `application/x-yaml` media type.
  yaml('application/x-yaml'),

  /// YAML data using the `application/yaml` media type.
  yaml2('application/yaml'),

  /// TOML data.
  toml('application/toml'),

  /// An unrecognized or unsupported media type.
  unknown('unknown');

  /// Creates a MIME type with its wire-format value.
  const MimeType(this.value);

  /// The MIME type string used in HTTP headers.
  final String value;
}

/// Selects the default binding for an HTTP method and content type.
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
