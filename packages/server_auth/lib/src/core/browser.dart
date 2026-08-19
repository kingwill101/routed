/// Typed browser-request protections shared by framework adapters.
final class AuthBrowserProtectionOptions {
  const AuthBrowserProtectionOptions({
    this.enabled = true,
    this.allowedOrigins = const <String>[],
    this.requireOrigin = false,
    this.enforceFetchMetadata = true,
  });

  /// Whether adapters should apply browser-request checks.
  final bool enabled;

  /// Explicit browser origins allowed to call state-changing auth routes.
  ///
  /// Origins must include scheme and host, for example
  /// `https://app.example.com`. Wildcards are not supported.
  final List<String> allowedOrigins;

  /// Whether a state-changing request must include an `Origin` header.
  ///
  /// Keep this false when supporting non-browser clients that do not send the
  /// header. Fetch Metadata and CSRF checks still apply when available.
  final bool requireOrigin;

  /// Whether adapters should reject Fetch Metadata `cross-site` requests
  /// unless their origin is explicitly allowed.
  final bool enforceFetchMetadata;

  AuthBrowserProtectionOptions copyWith({
    bool? enabled,
    List<String>? allowedOrigins,
    bool? requireOrigin,
    bool? enforceFetchMetadata,
  }) {
    return AuthBrowserProtectionOptions(
      enabled: enabled ?? this.enabled,
      allowedOrigins: allowedOrigins ?? this.allowedOrigins,
      requireOrigin: requireOrigin ?? this.requireOrigin,
      enforceFetchMetadata: enforceFetchMetadata ?? this.enforceFetchMetadata,
    );
  }
}
