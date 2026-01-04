import 'dart:async';

import 'package:routed/src/binding/multipart.dart';
import 'package:routed/src/context/context.dart';

import 'form.dart' show FormBinding;
import 'json.dart' show JsonBinding;
import 'multipart.dart' show MultipartBinding;
import 'query.dart' show QueryBinding;
import 'uri.dart' show UriBinding;

// For XML parsing you might use a third-party package like `xml`:
// import 'package:xml/xml.dart';

// Suppose we have a Request class with:
//   - method (String): The HTTP method of the request (e.g., GET, POST).
//   - contentType (String): The MIME type of the request body (e.g., application/json).
//   - body (Future<Uint8List>): A Future that resolves to the body bytes of the request.
//   - queryParameters (Map<String, String>): A map of query parameters from the request URL.
//   - etc.

/// Interface for objects that can be bound from a map of data.
abstract class Bindable {
  /// Binds the object properties from the given [data].
  void bind(Map<String, dynamic> data);
}

/// The `Binding` interface, analogous to Gin's "Binding".
/// This interface defines the contract for binding and validating request data.
abstract class Binding {
  /// The name of the binding.
  String get name;

  /// The MIME type associated with this binding.
  MimeType? get mimeType;

  /// Binds data from the request context to the given instance.
  ///
  /// [context] - The context of the engine containing request data.
  /// [instance] - The instance to which the data should be bound.
  Future<T> bind<T>(EngineContext context, T instance);

  /// Validates the data from the request context.
  ///
  /// [context] - The context of the engine containing request data.
  /// [data] - A map of data to be validated.
  Future<void> validate(
    EngineContext context,
    Map<String, String> data, {
    bool bail = false,
    Map<String, String>? messages,
  });
}

// Create singleton instances of each binding type.
final jsonBinding = JsonBinding();
final formBinding = FormBinding();
final uriBinding = UriBinding();
final multipartBinding = MultipartBinding();
final queryBinding = QueryBinding();

/// Common MIME types (mirroring Gin's constants).
/// These are used to determine the type of data in the request body.
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

  /// The string representation of the MIME type.
  final String value;

  /// Constructor for the MIME type enum.
  const MimeType(this.value);
}

/// Return a default binding given [method] and [contentType].
///
/// [method] - The HTTP method of the request (e.g., GET, POST).
/// [contentType] - The MIME type of the request body.
///
/// Returns the appropriate binding based on the method and content type.
Binding defaultBinding(String method, String contentType) {
  // If the method is GET, use the QueryBinding.
  if (method.toUpperCase() == 'GET') {
    return QueryBinding();
  }
  // Determine the MIME type from the content type.
  final mime =
      MimeType.values.where((m) => m.value == contentType).firstOrNull ?? "";
  // Return the appropriate binding based on the MIME type.
  switch (mime) {
    case MimeType.json:
      return jsonBinding;
    case MimeType.xml:
    case MimeType.xml2:
      throw UnimplementedError('XML binding not yet supported.');
    case MimeType.multipartPostForm:
      return multipartBinding;
    case MimeType.postForm:
      return formBinding;
    default:
      return formBinding;
  }
}
