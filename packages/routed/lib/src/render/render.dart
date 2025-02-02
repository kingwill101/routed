import 'dart:async';

import 'package:routed/src/response.dart';

/// The Render interface is designed to be implemented by various formats such as JSON, XML, HTML, etc.
/// It provides a contract for rendering data to a response and writing the appropriate content type to the response headers.
abstract class Render {
  /// Renders data to the given [response].
  ///
  /// This method is responsible for taking the data that needs to be rendered and writing it to the [response].
  /// The implementation of this method can be synchronous or asynchronous, hence the return type is [FutureOr<void>].
  ///
  /// [response] - The response object where the rendered data will be written.
  FutureOr<void> render(Response response);

  /// Writes the content type to the headers of the given [response].
  ///
  /// This method sets the appropriate content type (e.g., 'application/json' for JSON, 'text/html' for HTML) in the response headers.
  /// It ensures that the client receiving the response knows how to interpret the data.
  ///
  /// [response] - The response object where the content type header will be set.
  void writeContentType(Response response);
}
