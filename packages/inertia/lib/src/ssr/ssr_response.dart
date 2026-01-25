/// Defines the response payload from an SSR gateway.
///
/// ```dart
/// final response = SsrResponse(body: html, head: headTags);
/// ```
class SsrResponse {
  /// Creates an SSR response payload.
  const SsrResponse({
    required this.body,
    required this.head,
    this.statusCode = 200,
  });

  /// The rendered HTML body.
  final String body;

  /// The rendered HTML head content.
  final String head;

  /// The HTTP status code returned by the SSR server.
  final int statusCode;
}
