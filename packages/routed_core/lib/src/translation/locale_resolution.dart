library;

/// Looks up a value by [name] from a particular source (headers, query, etc.).
typedef LocaleLookup = String? Function(String name);

/// Encapsulates the data available to locale resolvers.
class LocaleResolutionContext {
  /// Creates a context with individual lookups for each source.
  LocaleResolutionContext({
    required this.header,
    required this.query,
    required this.cookie,
    this.sessionValue,
  });

  /// Header lookup (case-insensitive).
  final LocaleLookup header;

  /// Query parameter lookup.
  final LocaleLookup query;

  /// Cookie lookup.
  final LocaleLookup cookie;

  /// Session lookup, if sessions are enabled.
  final LocaleLookup? sessionValue;
}
