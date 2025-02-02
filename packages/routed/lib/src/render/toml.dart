import 'package:toml/toml.dart';
import 'package:routed/src/render/render.dart';
import 'package:routed/src/response.dart';

/// A class that implements the [Render] interface to render data in TOML format.
class TomlRender implements Render {
  /// A map containing the data to be serialized to TOML format.
  final Map<String, dynamic> data;

  /// Constructor for [TomlRender] that initializes the [data] field.
  TomlRender(this.data);

  /// Renders the response by serializing the [data] to TOML format and writing it to the response.
  ///
  /// This method first sets the content type of the response to 'application/toml; charset=utf-8'
  /// by calling [writeContentType]. It then serializes the [data] to a TOML string using the
  /// `TomlDocument.fromMap` method and writes the resulting TOML string to the response.
  ///
  /// - Parameter response: The [Response] object to which the TOML data will be written.
  @override
  void render(Response response) {
    // Set the content type of the response to 'application/toml; charset=utf-8'.
    writeContentType(response);

    // Serialize the data map to a TOML string.
    final tomlData = TomlDocument.fromMap(data).toString();

    // Write the serialized TOML data to the response.
    response.write(tomlData);
  }

  /// Sets the content type of the response to 'application/toml; charset=utf-8'.
  ///
  /// This method modifies the headers of the [response] to indicate that the content type
  /// of the response is TOML with UTF-8 character encoding.
  ///
  /// - Parameter response: The [Response] object whose headers will be modified.
  @override
  void writeContentType(Response response) {
    response.headers.set('Content-Type', 'application/toml; charset=utf-8');
  }
}
