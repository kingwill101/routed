import 'dart:convert';
import 'package:routed/src/render/render.dart';
import 'package:routed/src/response.dart';

/// A class that implements the [Render] interface to render JSON data.
class JsonRender implements Render {
  /// The data to be rendered as JSON.
  final dynamic data;

  /// Constructor to initialize the [JsonRender] with the given [data].
  ///
  /// The [data] parameter is the dynamic data that will be converted to JSON format.
  JsonRender(this.data);

  /// Renders the JSON data to the [response].
  ///
  /// This method first sets the Content-Type header to 'application/json; charset=utf-8'
  /// by calling [writeContentType]. It then converts the [data] to a JSON string using
  /// [jsonEncode] and writes this JSON string to the [response].
  @override
  void render(Response response) {
    writeContentType(response);
    final jsonData = jsonEncode(data);
    response.write(jsonData);
  }

  /// Sets the Content-Type header to 'application/json; charset=utf-8'.
  ///
  /// This method sets the 'Content-Type' header of the [response] to indicate that the
  /// content being returned is JSON encoded in UTF-8.
  @override
  void writeContentType(Response response) {
    response.headers.set('Content-Type', 'application/json; charset=utf-8');
  }
}

/// A class that implements the [Render] interface to render indented JSON data.
class IndentedJsonRender implements Render {
  /// The data to be rendered as indented JSON.
  final dynamic data;

  /// Constructor to initialize the [IndentedJsonRender] with the given [data].
  ///
  /// The [data] parameter is the dynamic data that will be converted to indented JSON format.
  IndentedJsonRender(this.data);

  /// Renders the indented JSON data to the [response].
  ///
  /// This method first sets the Content-Type header to 'application/json; charset=utf-8'
  /// by calling [writeContentType]. It then converts the [data] to an indented JSON string
  /// using a [JsonEncoder] with an indent of two spaces and writes this JSON string to the [response].
  @override
  void render(Response response) {
    writeContentType(response);
    final encoder = const JsonEncoder.withIndent('  ');
    final jsonData = encoder.convert(data);
    response.write(jsonData);
  }

  /// Sets the Content-Type header to 'application/json; charset=utf-8'.
  ///
  /// This method sets the 'Content-Type' header of the [response] to indicate that the
  /// content being returned is JSON encoded in UTF-8.
  @override
  void writeContentType(Response response) {
    response.headers.set('Content-Type', 'application/json; charset=utf-8');
  }
}

/// A class that implements the [Render] interface to render ASCII-safe JSON data.
class AsciiJsonRender implements Render {
  /// The data to be rendered as ASCII-safe JSON.
  final dynamic data;

  /// Constructor to initialize the [AsciiJsonRender] with the given [data].
  ///
  /// The [data] parameter is the dynamic data that will be converted to ASCII-safe JSON format.
  AsciiJsonRender(this.data);

  /// Renders the ASCII-safe JSON data to the [response].
  ///
  /// This method first sets the Content-Type header to 'application/json; charset=utf-8'
  /// by calling [writeContentType]. It then converts the [data] to a JSON string using
  /// [jsonEncode]. Non-ASCII characters in the JSON string are escaped to ensure the
  /// JSON data is ASCII-safe. The resulting JSON string is then written to the [response].
  @override
  void render(Response response) {
    writeContentType(response);

    String jsonData = jsonEncode(data);

    // Escape non-ASCII characters
    StringBuffer buffer = StringBuffer();
    for (int rune in jsonData.runes) {
      if (rune <= 127) {
        buffer.writeCharCode(rune);
      } else {
        buffer.write('\\u');
        buffer.write(rune.toRadixString(16).padLeft(4, '0'));
      }
    }

    response.write(buffer.toString());
  }

  /// Sets the Content-Type header to 'application/json; charset=utf-8'.
  ///
  /// This method sets the 'Content-Type' header of the [response] to indicate that the
  /// content being returned is JSON encoded in UTF-8.
  @override
  void writeContentType(Response response) {
    response.headers.set('Content-Type', 'application/json; charset=utf-8');
  }
}

/// A class that implements the [Render] interface to render JSONP data.
class JsonpRender implements Render {
  /// The callback function name for JSONP.
  final String callback;

  /// The data to be rendered as JSONP.
  final dynamic data;

  /// Constructor to initialize the [JsonpRender] with the given [callback] and [data].
  ///
  /// The [callback] parameter is the name of the JavaScript callback function to be used
  /// for JSONP. The [data] parameter is the dynamic data that will be converted to JSONP format.
  JsonpRender(this.callback, this.data);

  /// Renders the JSONP data to the [response].
  ///
  /// This method first sets the Content-Type header to 'application/javascript; charset=utf-8'
  /// by calling [writeContentType]. It then converts the [data] to a JSON string using
  /// [jsonEncode]. The JSON string is wrapped within the callback function specified by
  /// [callback]. The resulting JSONP string is then written to the [response].
  @override
  void render(Response response) {
    writeContentType(response);

    // Serialize data to JSON
    String jsonData = jsonEncode(data);

    // Escape the callback function name to prevent XSS
    String escapedCallback = Uri.encodeComponent(callback);

    String jsonpData;
    if (escapedCallback.isEmpty) {
      // If no callback provided, just return the JSON data
      jsonpData = jsonData;
    } else {
      // Wrap the JSON data within the callback function
      jsonpData = '$escapedCallback($jsonData);';
    }

    // Write the JSONP data to the response
    response.write(jsonpData);
  }

  /// Sets the Content-Type header to 'application/javascript; charset=utf-8'.
  ///
  /// This method sets the 'Content-Type' header of the [response] to indicate that the
  /// content being returned is JavaScript encoded in UTF-8.
  @override
  void writeContentType(Response response) {
    response.headers
        .set('Content-Type', 'application/javascript; charset=utf-8');
  }
}

/// A class that implements the [Render] interface to render secure JSON data.
class SecureJsonRender implements Render {
  /// The prefix to be added to the JSON data for security.
  final String prefix;

  /// The data to be rendered as secure JSON.
  final dynamic data;

  /// Constructor to initialize the [SecureJsonRender] with the given [data] and optional [prefix].
  ///
  /// The [data] parameter is the dynamic data that will be converted to secure JSON format.
  /// The [prefix] parameter is an optional string that will be prepended to the JSON data
  /// to prevent JSON hijacking. The default value for [prefix] is ")]}',\n".
  SecureJsonRender(this.data, {this.prefix = ")]}',\n"});

  /// Renders the secure JSON data to the [response].
  ///
  /// This method first sets the Content-Type header to 'application/json; charset=utf-8'
  /// by calling [writeContentType]. It then converts the [data] to a JSON string using
  /// [jsonEncode]. If the JSON data is an array, the [prefix] is prepended to the JSON string
  /// to prevent JSON hijacking. The resulting JSON string is then written to the [response].
  @override
  void render(Response response) {
    writeContentType(response);

    // Serialize data to JSON
    String jsonData = jsonEncode(data);

    // Determine if data is an array
    bool isArray = jsonData.startsWith('[') && jsonData.endsWith(']');

    String outputData;

    if (isArray) {
      // If data is an array, prepend the prefix
      outputData = '$prefix$jsonData';
    } else {
      // Otherwise, just output the JSON data
      outputData = jsonData;
    }

    // Write the output data to the response
    response.write(outputData);
  }

  /// Sets the Content-Type header to 'application/json; charset=utf-8'.
  ///
  /// This method sets the 'Content-Type' header of the [response] to indicate that the
  /// content being returned is JSON encoded in UTF-8.
  @override
  void writeContentType(Response response) {
    response.headers.set('Content-Type', 'application/json; charset=utf-8');
  }
}
