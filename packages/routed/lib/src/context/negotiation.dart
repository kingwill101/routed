part of 'context.dart';

typedef NegotiatedResponseBuilder = FutureOr<Response> Function();

extension NegotiationContext on EngineContext {
  /// Whether the client prefers a JSON response.
  ///
  /// Returns `true` when:
  /// - The `Accept` header explicitly includes `application/json` or
  ///   a JSON-compatible media type (`+json` suffix),
  /// - The request was sent via `XMLHttpRequest` (AJAX), or
  /// - The request's `Content-Type` is JSON (API clients typically
  ///   send and expect the same format).
  ///
  /// This is the primary signal used to decide between HTML and JSON
  /// error responses.
  bool get wantsJson {
    final accept =
        request.headers.value(HttpHeaders.acceptHeader)?.toLowerCase() ?? '';
    if (accept.contains('application/json') || accept.contains('+json')) {
      return true;
    }
    // XHR requests from JavaScript frameworks (Axios, fetch with
    // X-Requested-With, jQuery, etc.) generally expect JSON.
    final xhr = request.headers.value('x-requested-with')?.toLowerCase() ?? '';
    if (xhr == 'xmlhttprequest') {
      return true;
    }
    // If the client sent JSON, it likely expects JSON back.
    final contentType =
        request.headers.contentType?.mimeType.toLowerCase() ?? '';
    if (contentType == 'application/json') {
      return true;
    }
    return false;
  }

  /// Whether the client accepts HTML responses.
  ///
  /// Returns `true` when the `Accept` header includes `text/html` or
  /// `application/xhtml+xml`. Browsers typically send these.
  bool get acceptsHtml {
    final accept =
        request.headers.value(HttpHeaders.acceptHeader)?.toLowerCase() ?? '';
    return accept.contains('text/html') ||
        accept.contains('application/xhtml+xml');
  }

  /// Whether the client accepts the given [mimeType].
  ///
  /// Performs a simple substring check against the `Accept` header.
  /// For full quality-factor negotiation use [negotiateContentType].
  bool accepts(String mimeType) {
    final accept =
        request.headers.value(HttpHeaders.acceptHeader)?.toLowerCase() ?? '';
    return accept.contains(mimeType.toLowerCase());
  }

  /// Renders an error response in the format the client expects.
  ///
  /// Uses [wantsJson] and [acceptsHtml] to pick between JSON, HTML,
  /// and plain-text representations. The [statusCode] is set on the
  /// response, [message] provides a human-readable summary, and
  /// [jsonBody] (when supplied) overrides the default JSON structure.
  ///
  /// The HTML representation is a minimal self-contained page suitable
  /// for display in a browser.
  Response errorResponse({
    required int statusCode,
    required String message,
    Map<String, dynamic>? jsonBody,
  }) {
    if (wantsJson) {
      return ContextRender(this).json(
        jsonBody ?? {'error': message, 'status': statusCode},
        statusCode: statusCode,
      );
    }
    if (acceptsHtml) {
      // Minimal, self-contained HTML error page.
      final escaped = _errorHtmlEscape(message);
      final body =
          '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$statusCode — $escaped</title>
<style>
  body { font-family: system-ui, -apple-system, sans-serif; display: flex;
         justify-content: center; align-items: center; min-height: 100vh;
         margin: 0; background: #f8f9fa; color: #212529; }
  .error { text-align: center; }
  h1 { font-size: 4rem; margin: 0; font-weight: 300; color: #868e96; }
  p  { font-size: 1.25rem; margin: .5rem 0 0; }
</style>
</head>
<body>
  <div class="error">
    <h1>$statusCode</h1>
    <p>$escaped</p>
  </div>
</body>
</html>''';
      response.statusCode = statusCode;
      response.headers.contentType = ContentType.html;
      response.write(body);
      return response;
    }
    // Fall back to plain text.
    return ContextRender(this).string(message, statusCode: statusCode);
  }

  /// Negotiates the best media type from [supported] based on the request's
  /// `Accept` header. Returns `null` when no supported value satisfies the
  /// header.
  NegotiatedMediaType? negotiateContentType(
    Iterable<String> supported, {
    String? defaultType,
    bool addVaryHeader = true,
  }) {
    final supportedList = supported.toList(growable: false);
    final acceptHeader = request.headers.value(HttpHeaders.acceptHeader);
    final negotiated = ContentNegotiator.negotiate(
      acceptHeader,
      supportedList,
      defaultType: defaultType,
    );
    if (negotiated != null && addVaryHeader) {
      _ensureVaryAccept();
    }
    return negotiated;
  }

  /// Executes the builder corresponding to the negotiated media type from [offers].
  ///
  /// When negotiation fails, returns a 406 response (status can be customised via
  /// [notAcceptableStatus]). The selected builder is responsible for writing the
  /// response body; if it does not set a `Content-Type`, this helper applies the
  /// negotiated one.
  Future<Response> negotiate(
    Map<String, NegotiatedResponseBuilder> offers, {
    String? defaultType,
    int notAcceptableStatus = HttpStatus.notAcceptable,
    bool addVaryHeader = true,
  }) async {
    if (offers.isEmpty) {
      if (response.statusCode == HttpStatus.ok) {
        response.statusCode = notAcceptableStatus;
      }
      return response;
    }

    final selection = negotiateContentType(
      offers.keys,
      defaultType: defaultType,
      addVaryHeader: addVaryHeader,
    );

    if (selection == null) {
      if (addVaryHeader) {
        _ensureVaryAccept();
      }
      if (response.statusCode == HttpStatus.ok) {
        response.statusCode = notAcceptableStatus;
      }
      return response;
    }

    final builder = offers[selection.value];
    if (builder == null) {
      if (response.statusCode == HttpStatus.ok) {
        response.statusCode = notAcceptableStatus;
      }
      return response;
    }

    final result = await builder();
    if (response.headers.contentType == null) {
      try {
        response.headers.contentType = ContentType.parse(selection.value);
      } catch (_) {
        // Ignore invalid content-type strings, builders can set a custom header.
      }
    }
    return result;
  }

  void _ensureVaryAccept() {
    final existing = response.headers[HttpHeaders.varyHeader];
    if (existing != null) {
      final hasAccept = existing.any(
        (value) => value
            .split(',')
            .map((part) => part.trim().toLowerCase())
            .contains('accept'),
      );
      if (hasAccept) {
        return;
      }
    }
    response.headers.add(HttpHeaders.varyHeader, 'Accept');
  }
}

/// Escapes HTML special characters for safe embedding in error pages.
String _errorHtmlEscape(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
