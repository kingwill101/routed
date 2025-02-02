import 'dart:async';
import 'dart:io';
import 'package:routed/src/render/render.dart';
import 'package:routed/src/response.dart';

/// A class that implements the [Render] interface to handle rendering
/// of a response using a stream of bytes.
class ReaderRender implements Render {
  /// The MIME type of the content being rendered.
  final String contentType;

  /// The length of the content in bytes, if known.
  final int? contentLength;

  /// A stream of byte lists that represents the content to be rendered.
  final Stream<List<int>> reader;

  /// Additional headers to be included in the response.
  final Map<String, String>? headers;

  /// Constructs a [ReaderRender] with the given parameters.
  ///
  /// The [contentType] parameter is required and specifies the MIME type
  /// of the content. The [reader] parameter is also required and provides
  /// the stream of bytes to be rendered. The [contentLength] and [headers]
  /// parameters are optional.
  ReaderRender({
    required this.contentType,
    this.contentLength,
    required this.reader,
    this.headers,
  });

  /// Renders the response by writing headers and streaming the content.
  ///
  /// This method first writes the content type and any additional headers
  /// to the response. If the content length is known, it is also written
  /// to the response headers. The headers are sent immediately before
  /// streaming the content. If an error occurs during streaming, the
  /// response status is set to 500 (Internal Server Error) and an error
  /// message is written to the response.
  @override
  Future<void> render(Response response) async {
    writeContentType(response);

    if (contentLength != null && contentLength! >= 0) {
      response.headers.set('Content-Length', contentLength.toString());
    }

    if (headers != null) {
      _writeHeaders(response, headers!);
    }

    // Ensure headers are sent before writing the body
    response.writeHeaderNow();

    try {
      await response.addStream(reader);
    } catch (err) {
      // Handle any errors during streaming
      response.statusCode = HttpStatus.internalServerError;
      response.write('Internal Server Error');
    }
  }

  /// Writes the content type to the response headers.
  ///
  /// This method sets the 'Content-Type' header of the response to the
  /// value specified by the [contentType] property.
  @override
  void writeContentType(Response response) {
    response.headers.set('Content-Type', contentType);
  }

  /// Writes additional headers to the response.
  ///
  /// This method iterates over the provided [headers] map and sets each
  /// header in the response, provided that the header is not already set.
  void _writeHeaders(Response response, Map<String, String> headers) {
    headers.forEach((key, value) {
      if (response.headers.value(key) == null) {
        response.headers.set(key, value);
      }
    });
  }
}
