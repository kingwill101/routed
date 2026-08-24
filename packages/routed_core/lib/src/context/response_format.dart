part of 'context.dart';

/// Client content-type preference helpers used by the engine error path.
///
/// Full Accept negotiation lives in `package:routed_http`.
extension EngineContextResponseFormat on EngineContext {
  /// Whether the request prefers a JSON response.
  bool get wantsJson {
    final accept =
        request.headers.value(HttpHeaders.acceptHeader)?.toLowerCase() ?? '';
    if (accept.contains('application/json') || accept.contains('+json')) {
      return true;
    }
    final xhr = request.headers.value('x-requested-with')?.toLowerCase() ?? '';
    if (xhr == 'xmlhttprequest') {
      return true;
    }
    final contentType =
        request.headers.contentType?.mimeType.toLowerCase() ?? '';
    if (contentType == 'application/json') {
      return true;
    }
    return false;
  }

  /// Whether the request accepts an HTML response.
  bool get acceptsHtml {
    final accept =
        request.headers.value(HttpHeaders.acceptHeader)?.toLowerCase() ?? '';
    return accept.contains('text/html') ||
        accept.contains('application/xhtml+xml');
  }

  /// Writes an error response in the format preferred by the request.
  Response errorResponse({
    required int statusCode,
    required String message,
    Map<String, dynamic>? jsonBody,
  }) {
    if (wantsJson) {
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode(jsonBody ?? {'error': message, 'status': statusCode}),
      );
      return response;
    }
    if (acceptsHtml) {
      final escaped = message
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;');
      final body =
          '<!DOCTYPE html>\n'
          '<html lang="en">\n'
          '<head><meta charset="utf-8"><title>$statusCode</title></head>\n'
          '<body><h1>$statusCode</h1><p>$escaped</p></body>\n'
          '</html>';
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.html;
      response.write(body);
      return response;
    }
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.text;
    response.write(message);
    return response;
  }
}
