part of 'context.dart';

typedef NegotiatedResponseBuilder = FutureOr<Response> Function();

extension NegotiationContext on EngineContext {
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
