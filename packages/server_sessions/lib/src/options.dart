// Dart equivalent of Gorilla's `Options` struct, holding cookie-related config.

import 'dart:io';

/// Cookie attributes and lifetime defaults applied to a [Session].
class SessionOptions {
  /// The cookie path, defaulting to `/`.
  final String? path;

  /// The cookie domain, when one is configured.
  final String? domain;

  /// Whether this cookie requires HTTPS.
  final bool? secure;

  /// Whether this cookie is marked `HttpOnly`.
  final bool? httpOnly;

  /// Whether this cookie is partitioned.
  final bool? partitioned;

  /// The cookie's [SameSite] policy.
  final SameSite? sameSite;

  /// The cookie lifetime in seconds.
  ///
  /// A negative value requests deletion. A null value lets the store choose
  /// its default lifetime. Store implementations define how zero is handled;
  /// for example, file-backed storage treats it as non-expiring, while
  /// server-side stores may treat an effective zero lifetime as deletion.
  int? _maxAge;

  /// The configured cookie lifetime in seconds.
  int? get maxAge => _maxAge;

  /// Creates cookie options with the supplied attributes.
  SessionOptions({
    this.path = '/',
    this.domain,
    int? maxAge,
    this.secure,
    this.httpOnly,
    this.partitioned,
    this.sameSite,
  }) : _maxAge = maxAge;

  /// Creates a copy with the supplied non-null values replaced.
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

  /// Updates the cookie lifetime to [value] seconds.
  void setMaxAge(int? value) {
    _maxAge = value;
  }

  /// Converts these options to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'path': path,
    'domain': domain,
    'maxAge': _maxAge,
    'secure': secure,
    'httpOnly': httpOnly,
    'partitioned': partitioned,
    'sameSite': sameSite?.name,
  };

  /// Creates options from a map produced by [toJson].
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

  /// Creates a copy that preserves every configured option.
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
