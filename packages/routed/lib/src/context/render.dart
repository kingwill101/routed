part of 'context.dart';

extension ContextRender on EngineContext {
  /// Renders the response using the provided renderer.
  ///
  /// This method sets the status code of the response and uses the provided
  /// renderer to generate the response body. If the status code does not allow
  /// a body, it only writes the content type header and sends the response headers.
  ///
  /// If an error occurs during rendering, it logs the error and aborts the response.
  ///
  /// - Parameters:
  ///   - statusCode: The HTTP status code to set for the response.
  ///   - renderer: The renderer to use for generating the response body.
  Future<void> render(int statusCode, Render renderer) async {
    status(statusCode);

    if (!_bodyAllowedForStatus(statusCode)) {
      renderer.writeContentType(_response);
      _response.writeHeaderNow();
      return;
    }

    try {
      await renderer.render(_response);
    } catch (err) {
      addError('Render error: $err');
      abort();
    }
  }

  /// Renders a JSON response.
  ///
  /// - Parameters:
  ///   - data: The data to serialize to JSON.
  ///   - statusCode: The HTTP status code to set for the response (default is 200).
  void json(dynamic data, {int statusCode = HttpStatus.ok}) {
    render(statusCode, JsonRender(data));
  }

  /// Renders a JSONP response.
  ///
  /// - Parameters:
  ///   - data: The data to serialize to JSONP.
  ///   - callback: The JSONP callback function name (default is "callback").
  ///   - statusCode: The HTTP status code to set for the response (default is 200).
  void jsonp(dynamic data,
      {String callback = "callback", int statusCode = HttpStatus.ok}) {
    render(statusCode, JsonpRender(callback, data));
  }

  /// Renders an indented JSON response.
  ///
  /// - Parameters:
  ///   - data: The data to serialize to indented JSON.
  ///   - statusCode: The HTTP status code to set for the response (default is 200).
  void indentedJson(dynamic data, {int statusCode = HttpStatus.ok}) {
    render(statusCode, IndentedJsonRender(data));
  }

  /// Renders a secure JSON response with a prefix.
  ///
  /// - Parameters:
  ///   - data: The data to serialize to JSON.
  ///   - statusCode: The HTTP status code to set for the response (default is 200).
  ///   - prefix: The prefix to prepend to the JSON response (default is ")]}',\n").
  void secureJson(dynamic data,
      {int statusCode = HttpStatus.ok, String prefix = ")]}',\n"}) {
    render(statusCode, SecureJsonRender(data, prefix: prefix));
  }

  /// Renders an ASCII JSON response.
  ///
  /// - Parameters:
  ///   - data: The data to serialize to ASCII JSON.
  ///   - statusCode: The HTTP status code to set for the response (default is 200).
  void asciiJson(dynamic data, {int statusCode = HttpStatus.ok}) {
    render(statusCode, AsciiJsonRender(data));
  }

  /// Renders a plain text response.
  ///
  /// - Parameters:
  ///   - content: The plain text content to send in the response.
  ///   - statusCode: The HTTP status code to set for the response (default is 200).
  void string(String content, {int statusCode = HttpStatus.ok}) {
    render(statusCode, StringRender(content));
  }

  /// Renders an XML response.
  ///
  /// - Parameters:
  ///   - data: The data to serialize to XML.
  ///   - statusCode: The HTTP status code to set for the response (default is 200).
  void xml(Map<String, dynamic> data, {int statusCode = HttpStatus.ok}) {
    render(statusCode, XMLRender(data));
  }

  /// Renders a YAML response.
  ///
  /// - Parameters:
  ///   - data: The data to serialize to YAML.
  ///   - statusCode: The HTTP status code to set for the response (default is 200).
  void yaml(Map<String, dynamic> data, {int statusCode = HttpStatus.ok}) {
    render(statusCode, YamlRender(data));
  }

  /// Renders a TOML response.
  ///
  /// - Parameters:
  ///   - data: The data to serialize to TOML.
  ///   - statusCode: The HTTP status code to set for the response (default is 200).
  void toml(Map<String, dynamic> data, {int statusCode = HttpStatus.ok}) {
    render(statusCode, TomlRender(data));
  }

  /// Renders a response with custom content type and data.
  ///
  /// - Parameters:
  ///   - contentType: The content type of the response.
  ///   - data: The data to send in the response.
  ///   - statusCode: The HTTP status code to set for the response (default is 200).
  void data(String contentType, List<int> data, {int statusCode = HttpStatus.ok}) {
    render(statusCode, DataRender(contentType, data));
  }

  /// Redirects the client to a different URL.
  ///
  /// - Parameters:
  ///   - url: The URL to redirect to.
  ///   - statusCode: The HTTP status code to set for the response .
  Future<void> redirect(String url,
      {int statusCode = HttpStatus.movedTemporarily}) async {
    await render(-1, RedirectRender(code: statusCode, location: url));
  }

  /// Renders an HTML response using a template engine.
  ///
  /// - Parameters:
  ///   - content: The name of the template to render.
  ///   - data: The data to pass to the template (default is an empty map).
  ///   - statusCode: The HTTP status code to set for the response (default is 200).
  ///
  /// Throws an exception if the template engine is not set.
  Future<void> html(String content,
      {Map<String, dynamic> data = const {},
      int statusCode = HttpStatus.ok}) async {
    if (_engine?.templateEngine == null) {
      throw Exception('Template engine not set');
    }
    await render(
      statusCode,
      HTMLRender(
          templateName: content, data: data, engine: _engine!.templateEngine!),
    );
  }

  /// Serves the specified file directly to the client.
  ///
  /// - Parameters:
  ///   - filePath: The path to the file to serve.
  ///
  /// If an error occurs while serving the file, it aborts the response with a 500 status code.
  Future<void> file(String filePath) async {
    try {
      final directory = p.dirname(filePath);
      final fileName = p.basename(filePath);
      final fileHandler = FileHandler(rootPath: directory);

      // Serve the file
      await fileHandler.serveFile(request.httpRequest, fileName);
    } catch (e) {
      abortWithError(HttpStatus.internalServerError, e.toString());
    }
  }

  /// Serves the specified directory directly to the client.
  ///
  /// - Parameters:
  ///   - dirPath: The path to the directory to serve.
  ///
  /// If an error occurs while serving the directory, it aborts the response with a 500 status code.
  Future<void> dir(String dirPath) async {
    try {
      final directory = p.dirname(dirPath);
      final dirName = p.basename(dirPath);
      final dirHandler = FileHandler(rootPath: directory);

      // Serve the directory
      await dirHandler.serveDirectory(request.httpRequest, dirName);
    } catch (e) {
      abortWithError(HttpStatus.internalServerError, e.toString());
    }
  }

  /// Serves the specified file as an attachment, prompting the browser to download it.
  ///
  /// - Parameters:
  ///   - filePath: The path to the file to serve as an attachment.
  ///   - filename: The name to use for the downloaded file (optional).
  ///
  /// If an error occurs while serving the file, it aborts the response with a 500 status code.
  Future<void> fileAttachment(String filePath, String? filename) async {
    try {
      final directory = p.dirname(filePath);
      final fileName = p.basename(filePath);
      final attachmentName = filename ?? fileName;
      final fileHandler = FileHandler(rootPath: directory);

      // Set the Content-Disposition header to attachment
      if (_isAscii(attachmentName)) {
        _response.addHeader('Content-Disposition',
            'attachment; filename="${_escapeQuotes(attachmentName)}"');
      } else {
        _response.addHeader('Content-Disposition',
            'attachment; filename*=UTF-8\'\'${Uri.encodeFull(attachmentName)}');
      }

      // Serve the file
      await fileHandler.serveFile(request.httpRequest, fileName);
    } catch (e) {
      abortWithError(HttpStatus.internalServerError, e.toString());
    }
  }

  /// Checks if a string contains only ASCII characters.
  ///
  /// - Parameters:
  ///   - s: The string to check.
  ///
  /// Returns true if the string contains only ASCII characters, false otherwise.
  bool _isAscii(String s) {
    return s.codeUnits.every((c) => c <= 127);
  }

  /// Escapes quotes in a string.
  ///
  /// - Parameters:
  ///   - s: The string to escape.
  ///
  /// Returns the escaped string.
  String _escapeQuotes(String s) {
    return s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  /// Renders a response from a stream reader.
  ///
  /// - Parameters:
  ///   - statusCode: The HTTP status code to set for the response.
  ///   - contentLength: The length of the content (optional).
  ///   - contentType: The content type of the response.
  ///   - reader: The stream reader to read the content from.
  ///   - extraHeaders: Additional headers to include in the response (optional).
  void dataFromReader(
      {required int statusCode,
      int? contentLength,
      required String contentType,
      required Stream<List<int>> reader,
      Map<String, String>? extraHeaders}) {
    render(
        statusCode,
        ReaderRender(
            contentType: contentType,
            contentLength: contentLength,
            reader: reader,
            headers: extraHeaders));
  }
}
