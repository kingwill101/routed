part of 'context.dart';

extension ContextRender on EngineContext {
  /// Renders the response using the provided renderer and returns the Response.
  FutureOr<Response> render(int statusCode, Render renderer) {
    // If the response has already been finalized or the context was aborted
    // (e.g. by a timeout), ignore subsequent render attempts.
    if (isAborted || _response.isClosed) {
      return _response;
    }

    if (_response.statusCode >= 100 && _response.statusCode < 200) {
      return _response;
    }

    status(statusCode);

    if (!_bodyAllowedForStatus(statusCode)) {
      renderer.writeContentType(_response);
      _response.writeHeaderNow();
      return _response;
    }

    try {
      final result = renderer.render(_response);
      if (result is Future<void>) {
        return result.then((_) => _response).catchError((err) {
          addError('Render error: $err');
          abort();
          return _response;
        });
      }
    } catch (err) {
      addError('Render error: $err');
      abort();
    }
    return _response;
  }

  Response json(dynamic data, {int statusCode = HttpStatus.ok}) {
    final effectiveStatus = _response.statusCode != HttpStatus.ok
        ? _response.statusCode
        : statusCode;
    final r = render(effectiveStatus, JsonRender(data));
    return r is Response ? r : _response;
  }

  Response jsonp(
    dynamic data, {
    String callback = "callback",
    int statusCode = HttpStatus.ok,
  }) {
    final r = render(statusCode, JsonpRender(callback, data));
    return r is Response ? r : _response;
  }

  Response indentedJson(dynamic data, {int statusCode = HttpStatus.ok}) {
    final r = render(statusCode, IndentedJsonRender(data));
    return r is Response ? r : _response;
  }

  Response secureJson(
    dynamic data, {
    int statusCode = HttpStatus.ok,
    String prefix = ")]}',\n",
  }) {
    final r = render(statusCode, SecureJsonRender(data, prefix: prefix));
    return r is Response ? r : _response;
  }

  Response asciiJson(dynamic data, {int statusCode = HttpStatus.ok}) {
    final r = render(statusCode, AsciiJsonRender(data));
    return r is Response ? r : _response;
  }

  Response string(String content, {int statusCode = HttpStatus.ok}) {
    final r = render(statusCode, StringRender(content));
    return r is Response ? r : _response;
  }

  Response xml(Map<String, dynamic> data, {int statusCode = HttpStatus.ok}) {
    final r = render(statusCode, XmlRender(data));
    return r is Response ? r : _response;
  }

  Response yaml(Map<String, dynamic> data, {int statusCode = HttpStatus.ok}) {
    final r = render(statusCode, YamlRender(data));
    return r is Response ? r : _response;
  }

  Response data(
    String contentType,
    List<int> data, {
    int statusCode = HttpStatus.ok,
  }) {
    final r = render(statusCode, DataRender(contentType, data));
    return r is Response ? r : _response;
  }

  Future<Response> redirect(
    String url, {
    int statusCode = HttpStatus.movedTemporarily,
  }) async {
    return await render(-1, RedirectRender(code: statusCode, location: url));
  }

  Future<Response> html(
    String content, {
    Map<String, dynamic> data = const {},
    int statusCode = HttpStatus.ok,
  }) async {
    return await render(
      statusCode,
      HtmlRender(content: content, data: data, engine: _engine!.viewEngine),
    );
  }

  Future<String> templateString({
    String? content,
    Map<String, dynamic> data = const {},
    String? templateName,
  }) async {
    if (_engine?.viewEngine == null && content == null) {
      throw Exception('Template engine not set');
    }

    if (content != null) {
      return content;
    }

    if (templateName == null) {
      throw Exception('Template name not set');
    }

    return await _engine!.viewEngine.renderFile(templateName);
  }

  Future<Response> template({
    String? content,
    Map<String, dynamic> data = const {},
    int statusCode = HttpStatus.ok,
    String? templateName,
  }) async {
    if (_engine?.viewEngine == null && content == null) {
      throw Exception('Template engine not set');
    }
    return await render(
      statusCode,
      HtmlRender(
        content: content,
        templateName: templateName,
        data: {
          ...data,
          kViewEngineContextKey: this,
        },
        engine: _engine!.viewEngine,
      ),
    );
  }

  Future<Response> file(String filePath) async {
    try {
      final directory = p.dirname(filePath);
      final fileName = p.basename(filePath);
      final fileHandler = FileHandler(rootPath: directory);

      await fileHandler.serveFile(this, fileName);
      return _response;
    } catch (e) {
      abortWithError(HttpStatus.internalServerError, e.toString());
      return _response;
    }
  }

  Future<Response> dir(String dirPath) async {
    try {
      final directory = p.dirname(dirPath);
      final dirName = p.basename(dirPath);
      final dirHandler = FileHandler(rootPath: directory);

      await dirHandler.serveDirectory(this, dirName);
      return _response;
    } catch (e) {
      abortWithError(HttpStatus.internalServerError, e.toString());
      return _response;
    }
  }

  Future<Response> fileAttachment(String filePath, String? filename) async {
    try {
      final directory = p.dirname(filePath);
      final fileName = p.basename(filePath);
      final attachmentName = filename ?? fileName;
      final fileHandler = FileHandler(rootPath: directory);

      if (_isAscii(attachmentName)) {
        _response.addHeader(
          'Content-Disposition',
          'attachment; filename="${_escapeQuotes(attachmentName)}"',
        );
      } else {
        _response.addHeader(
          'Content-Disposition',
          'attachment; filename*=UTF-8\'\'${Uri.encodeFull(attachmentName)}',
        );
      }

      await fileHandler.serveFile(this, fileName);
      return _response;
    } catch (e) {
      abortWithError(HttpStatus.internalServerError, e.toString());
      return _response;
    }
  }

  bool _isAscii(String s) {
    return s.codeUnits.every((c) => c <= 127);
  }

  String _escapeQuotes(String s) {
    return s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  Response dataFromReader({
    required int statusCode,
    int? contentLength,
    required String contentType,
    required Stream<List<int>> reader,
    Map<String, String>? extraHeaders,
  }) {
    final r = render(
      statusCode,
      ReaderRender(
        contentType: contentType,
        contentLength: contentLength,
        reader: reader,
        headers: extraHeaders,
      ),
    );
    return r is Response ? r : _response;
  }
}
