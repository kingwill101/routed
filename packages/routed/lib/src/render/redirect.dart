import 'dart:io';
import 'package:routed/src/render/render.dart';
import 'package:routed/src/response.dart';

/// A class that implements the [Render] interface to handle HTTP redirects.
class RedirectRender implements Render {
  /// The HTTP status code for the redirect.
  /// Must be a valid redirect status code (3xx) or 201 (Created).
  final int code;

  /// The URL to which the client is redirected.
  final String location;

  /// Creates an instance of [RedirectRender].
  ///
  /// The [code] parameter specifies the HTTP status code for the redirect.
  /// The [location] parameter specifies the URL to which the client is redirected.
  RedirectRender({
    required this.code,
    required this.location,
  });

  /// Overrides the [writeContentType] method from the [Render] interface.
  ///
  /// This method does not set any content type for redirects as it is not needed.
  @override
  void writeContentType(Response response) {
    // No content type needed for redirects
  }

  /// Overrides the [render] method from the [Render] interface.
  ///
  /// This method sets the HTTP status code and the Location header for the response.
  /// Throws an [Exception] if the status code is not a valid redirect status code.
  @override
  void render(Response response) {
    // Check if the status code is a valid redirect status code (3xx) or 201 (Created).
    if ((code < HttpStatus.multipleChoices ||
            code > HttpStatus.permanentRedirect) &&
        code != HttpStatus.created) {
      throw Exception('Cannot redirect with status code $code');
    }

    // Set the status code and Location header in the response.
    response.statusCode = code;
    response.headers.set(HttpHeaders.locationHeader, location);
  }
}
