import 'package:xml/xml.dart';
import 'package:routed/src/render/render.dart';
import 'package:routed/src/response.dart';

/// A class that implements the [Render] interface to render data as XML.
class XMLRender implements Render {
  /// The data to be rendered as XML.
  final dynamic data;

  /// Constructor to initialize the [XMLRender] with the given data.
  XMLRender(this.data);

  /// Renders the response by converting the data to XML and writing it to the response.
  @override
  void render(Response response) {
    // Set the content type of the response to 'application/xml'.
    writeContentType(response);

    // Serialize the data to XML format.
    final xmlData = _convertToXml(data);

    // Write the serialized XML data to the response with pretty formatting.
    response.write(xmlData.toXmlString(pretty: true));
  }

  /// Sets the 'Content-Type' header of the response to 'application/xml; charset=utf-8'.
  @override
  void writeContentType(Response response) {
    response.headers.set('Content-Type', 'application/xml; charset=utf-8');
  }

  /// Converts the given data to an [XmlDocument].
  ///
  /// This method uses an [XmlBuilder] to construct the XML document.
  /// If the data is a [Map], it iterates over the key-value pairs and builds XML elements.
  /// If the data is not a [Map], it wraps the data in a 'response' element.
  XmlDocument _convertToXml(dynamic data) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');

    if (data is Map<String, dynamic>) {
      data.forEach((key, value) {
        builder.element(key, nest: () {
          _buildXml(value, builder);
        });
      });
    } else {
      builder.element('response', nest: () {
        _buildXml(data, builder);
      });
    }

    return builder.buildDocument();
  }

  /// Recursively builds XML elements from the given data using the provided [XmlBuilder].
  ///
  /// If the data is a [Map], it iterates over the key-value pairs and creates nested elements.
  /// If the data is a [List], it creates 'item' elements for each value in the list.
  /// If the data is a primitive type, it converts the data to a string and adds it as text content.
  void _buildXml(dynamic data, XmlBuilder builder) {
    if (data is Map<String, dynamic>) {
      data.forEach((key, value) {
        builder.element(key, nest: () {
          _buildXml(value, builder);
        });
      });
    } else if (data is List) {
      for (var value in data) {
        builder.element('item', nest: () {
          _buildXml(value, builder);
        });
      }
    } else {
      builder.text(data?.toString() ?? '');
    }
  }
}
