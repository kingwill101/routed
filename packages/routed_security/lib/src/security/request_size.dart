/// Resolves the request content length from available metadata.
///
/// Returns `-1` when length is unknown.
int resolveContentLength({
  required int headersContentLength,
  required int requestContentLength,
  String? rawContentLength,
}) {
  var contentLength = headersContentLength;

  if (contentLength <= 0) {
    contentLength = requestContentLength;
  }

  if (contentLength <= 0) {
    final parsed = rawContentLength == null
        ? null
        : int.tryParse(rawContentLength);
    contentLength = parsed ?? -1;
  }

  return contentLength;
}

/// Returns `true` when request content length is known and exceeds [maxBytes].
bool exceedsRequestBodyLimit({
  required int maxBytes,
  required int headersContentLength,
  required int requestContentLength,
  String? rawContentLength,
}) {
  final contentLength = resolveContentLength(
    headersContentLength: headersContentLength,
    requestContentLength: requestContentLength,
    rawContentLength: rawContentLength,
  );

  return contentLength != -1 && contentLength > maxBytes;
}
