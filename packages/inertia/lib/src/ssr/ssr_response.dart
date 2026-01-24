/// Response from an Inertia SSR gateway
class SsrResponse {
  const SsrResponse({
    required this.body,
    required this.head,
    this.statusCode = 200,
  });
  final String body;
  final String head;
  final int statusCode;
}
