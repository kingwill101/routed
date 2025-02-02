import 'package:routed/src/render/render.dart';
import 'package:routed/src/response.dart';

/// A class that implements the [Render] interface to handle rendering of data.
/// This class is responsible for setting the content type and writing the data
/// to the response.
class DataRender implements Render {
  /// The MIME type of the content being rendered.
  final String contentType;

  /// The data to be rendered, represented as a list of bytes.
  final List<int> data;

  /// Constructs a [DataRender] instance with the specified [contentType] and [data].
  DataRender(this.contentType, this.data);

  /// Renders the response by setting the content type and writing the data.
  ///
  /// This method first sets the content type of the response by calling
  /// [writeContentType], and then writes the data to the response using
  /// [response.writeBytes].
  ///
  /// - Parameter response: The [Response] object to which the data will be written.
  @override
  void render(Response response) {
    writeContentType(response);
    response.writeBytes(data);
  }

  /// Sets the content type of the response.
  ///
  /// This method sets the 'Content-Type' header of the response to the value
  /// specified by the [contentType] property.
  ///
  /// - Parameter response: The [Response] object whose headers will be modified.
  @override
  void writeContentType(Response response) {
    response.headers.set('Content-Type', contentType);
  }
}
