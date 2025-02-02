/// Dart equivalent of Gorilla's `Options` struct, holding cookie-related config.
class Options {
  /// The cookie path (defaults to "/").
  String path;

  /// The cookie domain (optional).
  String? domain;

  /// MaxAge = 0 means no expiration set. MaxAge < 0 deletes cookie immediately.
  /// MaxAge > 0 means the cookie will expire in [MaxAge] seconds from now.
  int? maxAge;

  /// Whether this cookie requires HTTPS.
  bool? secure;

  /// Whether this cookie is marked HttpOnly.
  bool? httpOnly;

  /// Whether this cookie is partitioned (Dart's Cookie class may not support it fully).
  bool? partitioned;

  /// SameSite policy: "none", "lax", "strict", etc.
  ///
  /// In Gorilla, it's an enum from net/http. In Dart, you might store a string
  /// or design your own enum.
  String? sameSite;

  Options({
    this.path = '/',
    this.domain,
    this.maxAge,
    this.secure,
    this.httpOnly,
    this.partitioned,
    this.sameSite,
  });
}
