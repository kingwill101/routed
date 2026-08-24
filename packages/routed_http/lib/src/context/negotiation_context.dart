import 'dart:async';
import 'dart:io';

import 'package:routed_core/routed_core.dart';

import 'package:routed_http/src/http/negotiation.dart';

/// Builds a response for a selected negotiated media type.
typedef NegotiatedResponseBuilder = FutureOr<Response> Function();

/// Adds response negotiation helpers to an [EngineContext].
extension NegotiationContext on EngineContext {
  /// Selects a supported media type and optionally adds `Vary: Accept`.
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

  /// Executes the builder corresponding to the negotiated media type in
  /// [offers].
  ///
  /// When negotiation fails, returns a 406 response, or the configured
  /// [notAcceptableStatus]. The selected builder writes the response body; if
  /// it does not set a `Content-Type`, this helper applies the negotiated one.
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
      } on FormatException catch (_) {
        // Invalid content-type strings are left for builders to override.
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
