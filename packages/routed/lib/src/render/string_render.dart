import 'package:routed/src/render/render.dart';
import 'package:routed/src/response.dart';

/// A class that implements the [Render] interface to render a string response.
class StringRender implements Render {
  /// The content to be rendered as a string.
  final String content;

  /// Constructor for [StringRender] that initializes the content.
  ///
  /// Takes a [String] [content] which will be rendered in the response.
  StringRender(this.content);

  /// Renders the response by writing the content type and the content.
  ///
  /// This method first sets the content type of the response to 'text/plain'
  /// with UTF-8 charset by calling [writeContentType]. Then, it writes the
  /// [content] to the response.
  ///
  /// - Parameter [response]: The [Response] object where the content will be written.
  @override
  void render(Response response) {
    writeContentType(response);
    response.write(content);
  }

  /// Sets the content type of the response to 'text/plain' with UTF-8 charset.
  ///
  /// This method modifies the headers of the [response] to include the
  /// 'Content-Type' header with the value 'text/plain; charset=utf-8'.
  ///
  /// - Parameter [response]: The [Response] object whose headers will be modified.
  @override
  void writeContentType(Response response) {
    response.headers.set('Content-Type', 'text/plain; charset=utf-8');
  }
}
