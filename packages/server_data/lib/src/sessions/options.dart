// Dart equivalent of Gorilla's `Options` struct, holding cookie-related config.

import 'dart:io';

class SessionOptions {
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

  /// Cookie SameSite policy.
  final SameSite? sameSite;

  /// MaxAge = 0 means no expiration set
  /// MaxAge < 0 deletes cookie immediately
  /// MaxAge > 0 means the cookie will expire in [MaxAge] seconds from now
  int? _maxAge;

  /// Public getter for maxAge
  int? get maxAge => _maxAge;

  /// Constructor with named parameters and default values
  SessionOptions({
    this.path = '/',
    this.domain,
    int? maxAge,
    this.secure,
    this.httpOnly,
    this.partitioned,
    this.sameSite,
  }) : _maxAge = maxAge;

  /// Creates a new SessionOptions instance with updated values
  SessionOptions copyWith({
    String? path,
    String? domain,
    int? maxAge,
    bool? secure,
    bool? httpOnly,
    bool? partitioned,
    SameSite? sameSite,
  }) {
    return SessionOptions(
      path: path ?? this.path,
      domain: domain ?? this.domain,
      maxAge: maxAge ?? _maxAge,
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

  /// Converts SessionOptions to JSON representation
  Map<String, dynamic> toJson() => {
    'path': path,
    'domain': domain,
    'maxAge': _maxAge,
    'secure': secure,
    'httpOnly': httpOnly,
    'partitioned': partitioned,
    'sameSite': sameSite?.name,
  };

  /// Creates SessionOptions from JSON representation
  factory SessionOptions.fromJson(Map<String, dynamic> json) => SessionOptions(
    path: json['path'] as String?,
    domain: json['domain'] as String?,
    maxAge: json['maxAge'] as int?,
    secure: json['secure'] as bool?,
    httpOnly: json['httpOnly'] as bool?,
    partitioned: json['partitioned'] as bool?,
    sameSite: (json['sameSite'] as String?) != null
        ? SameSite.values.firstWhere((e) => e.name == json['sameSite'])
        : null,
  );

  /// Creates a copy of SessionOptions with all fields
  SessionOptions clone() => SessionOptions(
    path: path,
    domain: domain,
    maxAge: _maxAge,
    secure: secure,
    httpOnly: httpOnly,
    partitioned: partitioned,
    sameSite: sameSite,
  );
}
