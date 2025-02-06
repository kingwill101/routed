/// Dart equivalent of Gorilla's `Options` struct, holding cookie-related config.
class Options {
  /// The cookie path (defaults to "/")
  final String? path;

  /// The cookie domain (optional)
  final String? domain;

  /// Whether this cookie requires HTTPS
  final bool? secure;

  /// Whether this cookie is marked HttpOnly
  final bool? httpOnly;

  /// Whether this cookie is partitioned
  final bool? partitioned;

  /// SameSite policy: "none", "lax", "strict"
  final String? sameSite;

  /// MaxAge = 0 means no expiration set
  /// MaxAge < 0 deletes cookie immediately
  /// MaxAge > 0 means the cookie will expire in [MaxAge] seconds from now
  int? _maxAge;

  /// Public getter for maxAge
  int? get maxAge => _maxAge;

  /// Constructor with named parameters and default values
  Options({
    this.path = '/',
    this.domain,
    int? maxAge,
    this.secure,
    this.httpOnly,
    this.partitioned,
    this.sameSite,
  }) : _maxAge = maxAge;

  /// Creates a new Options instance with updated values
  Options copyWith({
    String? path,
    String? domain,
    int? maxAge,
    bool? secure,
    bool? httpOnly,
    bool? partitioned,
    String? sameSite,
  }) {
    return Options(
      path: path ?? this.path,
      domain: domain ?? this.domain,
      maxAge: maxAge ?? this._maxAge,
      secure: secure ?? this.secure,
      httpOnly: httpOnly ?? this.httpOnly,
      partitioned: partitioned ?? this.partitioned,
      sameSite: sameSite ?? this.sameSite,
    );
  }

  /// Updates the maxAge value
  void setMaxAge(int? value) {
    _maxAge = value;
  }

  /// Converts Options to JSON representation
  Map<String, dynamic> toJson() => {
        'path': path,
        'domain': domain,
        'maxAge': _maxAge,
        'secure': secure,
        'httpOnly': httpOnly,
        'partitioned': partitioned,
        'sameSite': sameSite,
      };

  /// Creates Options from JSON representation
  factory Options.fromJson(Map<String, dynamic> json) => Options(
        path: json['path'] as String?,
        domain: json['domain'] as String?,
        maxAge: json['maxAge'] as int?,
        secure: json['secure'] as bool?,
        httpOnly: json['httpOnly'] as bool?,
        partitioned: json['partitioned'] as bool?,
        sameSite: json['sameSite'] as String?,
      );

  /// Creates a copy of Options with all fields
  Options clone() => Options(
        path: path,
        domain: domain,
        maxAge: _maxAge,
        secure: secure,
        httpOnly: httpOnly,
        partitioned: partitioned,
        sameSite: sameSite,
      );
}
