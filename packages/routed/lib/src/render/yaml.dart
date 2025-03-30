import 'package:json2yaml/json2yaml.dart';
import 'package:routed/src/render/render.dart';
import 'package:routed/src/response.dart';

/// A class that implements the [Render] interface to render data as YAML.
class YamlRender implements Render {
  /// The data to be serialized to YAML.
  final Map<String, dynamic> data;

  /// Constructor for [YamlRender] that initializes the [data] field.
  YamlRender(this.data);

  /// Renders the response by serializing [data] to YAML and writing it to the response.
  ///
  /// This method first sets the content type of the response to 'application/x-yaml'
  /// and then serializes the [data] to YAML format using the `json2yaml` package.
  /// Finally, it writes the serialized YAML data to the response.
  ///
  /// [response] is the HTTP response object where the YAML data will be written.
  @override
  void render(Response response) {
    // Set the content type of the response to 'application/x-yaml'.
    writeContentType(response);

    // Serialize the data to YAML format.
    final yamlData = json2yaml(data);

    // Write the serialized YAML data to the response.
    response.write(yamlData);
  }

  /// Sets the content type of the response to 'application/x-yaml'.
  ///
  /// This method modifies the headers of the [response] to indicate that the content
  /// type is 'application/x-yaml' with UTF-8 character encoding.
  ///
  /// [response] is the HTTP response object whose headers will be modified.
  @override
  void writeContentType(Response response) {
    response.headers.set('Content-Type', 'application/x-yaml; charset=utf-8');
  }
}
