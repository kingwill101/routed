/// Resolves Cloudflare's host-provided client address from Fetch headers.
///
/// A Worker Fetch request has no socket remote address. Cloudflare supplies
/// the connecting address through `CF-Connecting-IP`, which the Fetch bridge
/// treats as the host-known remote address rather than as an application
/// forwarded header.
String? cloudflareClientIpFromHeaders(Map<String, Object?> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() != 'cf-connecting-ip') continue;
    final value = entry.value;
    final candidate = value is Iterable
        ? value
              .firstWhere(
                (item) => item.toString().trim().isNotEmpty,
                orElse: () => '',
              )
              .toString()
        : value?.toString() ?? '';
    final normalized = candidate.trim();
    return normalized.isEmpty ? null : normalized;
  }
  return null;
}
