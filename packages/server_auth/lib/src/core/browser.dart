/// Typed browser-request protections shared by framework adapters.
final class AuthBrowserProtectionOptions {
  /// Creates browser-request protections with the supplied policy values.
  ///
  /// The lists and set are retained as supplied. No origins or methods are
  /// canonicalized by this constructor.
  const AuthBrowserProtectionOptions({
    this.enabled = true,
    this.allowedOrigins = const <String>[],
    this.trustedOrigins = const <String>[],
    this.requireOrigin = false,
    this.enforceFetchMetadata = true,
    this.enforceReferrer = false,
    this.allowedMethods = const {'GET', 'POST', 'PUT', 'DELETE', 'PATCH'},
    this.requireContentType = false,
  });

  /// Strict browser policy for a production auth runtime.
  ///
  /// Enables Origin, Fetch Metadata, Referer fallback, and Content-Type
  /// checks, and makes [trustedOrigins] unmodifiable.
  AuthBrowserProtectionOptions.production({
    required Iterable<String> trustedOrigins,
  }) : enabled = true,
       allowedOrigins = const <String>[],
       trustedOrigins = List<String>.unmodifiable(trustedOrigins),
       requireOrigin = true,
       enforceFetchMetadata = true,
       enforceReferrer = true,
       allowedMethods = const {'GET', 'POST', 'PUT', 'DELETE', 'PATCH'},
       requireContentType = true;

  /// Relaxed browser policy for explicitly local development.
  ///
  /// This policy leaves origin and content-type requirements disabled while
  /// retaining the default Fetch Metadata setting.
  static const AuthBrowserProtectionOptions localDevelopment =
      AuthBrowserProtectionOptions();

  /// Whether adapters should apply browser-request checks.
  final bool enabled;

  /// Explicit browser origins allowed to call state-changing auth routes.
  ///
  /// Origins must include scheme and host, for example
  /// `https://app.example.com`. Wildcards are not supported.
  final List<String> allowedOrigins;

  /// Trusted origins for CSRF and origin validation.
  ///
  /// Requests from these origins are always allowed regardless of other
  /// checks. Use this for known frontend applications.
  final List<String> trustedOrigins;

  /// Whether a state-changing request must include an `Origin` header.
  ///
  /// Keep this false when supporting non-browser clients that do not send the
  /// header. Fetch Metadata and CSRF checks still apply when available.
  final bool requireOrigin;

  /// Whether adapters should reject Fetch Metadata `cross-site` requests
  /// unless their origin is explicitly allowed.
  final bool enforceFetchMetadata;

  /// Whether to validate the Referer header as a fallback for missing Origin.
  final bool enforceReferrer;

  /// Allowed HTTP methods for browser requests.
  final Set<String> allowedMethods;

  /// Whether to require Content-Type header on state-changing requests.
  final bool requireContentType;

  /// Returns a shallow policy copy with supplied values replaced.
  ///
  /// The copied lists and set are retained as supplied; origins and methods
  /// are not canonicalized.
  AuthBrowserProtectionOptions copyWith({
    bool? enabled,
    List<String>? allowedOrigins,
    List<String>? trustedOrigins,
    bool? requireOrigin,
    bool? enforceFetchMetadata,
    bool? enforceReferrer,
    Set<String>? allowedMethods,
    bool? requireContentType,
  }) {
    return AuthBrowserProtectionOptions(
      enabled: enabled ?? this.enabled,
      allowedOrigins: allowedOrigins ?? this.allowedOrigins,
      trustedOrigins: trustedOrigins ?? this.trustedOrigins,
      requireOrigin: requireOrigin ?? this.requireOrigin,
      enforceFetchMetadata: enforceFetchMetadata ?? this.enforceFetchMetadata,
      enforceReferrer: enforceReferrer ?? this.enforceReferrer,
      allowedMethods: allowedMethods ?? this.allowedMethods,
      requireContentType: requireContentType ?? this.requireContentType,
    );
  }
}
