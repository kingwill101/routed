import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server_sessions/src/options.dart';
import 'package:server_sessions/src/secure_cookie.dart';
import 'package:server_sessions/src/session.dart';
import 'package:server_sessions/src/store.dart';

/// A [SessionStore] implementation that stores the complete session in a
/// protected client cookie.
class CookieStore implements SessionStore {
  /// Creates a cookie-backed store using [codecs].
  ///
  /// The first codec encodes new cookies; later codecs are accepted as
  /// fallbacks for reading legacy cookies. [defaultOptions] apply to new
  /// sessions and default to a one-day, secure, HttpOnly cookie.
  CookieStore({
    required List<SecureCookie> codecs,
    SessionOptions? defaultOptions,
  }) : assert(
         codecs.isNotEmpty,
         'At least one SecureCookie codec is required.',
       ),
       _primaryCodec = codecs.first,
       _fallbackCodecs = codecs.length > 1 ? codecs.sublist(1) : const [],
       defaultOptions =
           defaultOptions ??
           SessionOptions(
             maxAge: 86400,
             secure: true,
             httpOnly: true,
             sameSite: SameSite.lax,
           );

  /// Primary codec used when encoding new payloads.
  final SecureCookie _primaryCodec;

  /// Fallback codecs accepted when decoding legacy cookies.
  final List<SecureCookie> _fallbackCodecs;

  /// Default options for sessions created by this store.
  final SessionOptions defaultOptions;

  /// Decodes the request cookie into a session or returns a new session.
  ///
  /// URI encoding and the configured codec chain are supported. Missing,
  /// malformed, or invalid cookies are treated as new sessions.
  @override
  Future<Session> read(SessionRequest request, String name) async {
    var cookie = request.cookies.firstWhere(
      (c) => c.name == name,
      orElse: () => Cookie(name, ''),
    );

    if (cookie.value.isEmpty) {
      final header = request.header(HttpHeaders.cookieHeader);
      if (header.isNotEmpty) {
        for (final entry in header.split(';')) {
          final trimmed = entry.trim();
          if (trimmed.isEmpty) continue;
          final separatorIndex = trimmed.indexOf('=');
          if (separatorIndex == -1) continue;
          final cookieName = trimmed.substring(0, separatorIndex).trim();
          if (cookieName != name) continue;
          final cookieValue = trimmed.substring(separatorIndex + 1).trim();
          if (cookieValue.isEmpty) continue;
          cookie = Cookie(cookieName, cookieValue);
          break;
        }
      }
    }

    if (cookie.value.isEmpty) {
      return Session(name: name, options: defaultOptions.clone());
    }

    var value = cookie.value;
    try {
      value = Uri.decodeComponent(value);
    } on Object {
      // Value was not URI-encoded; continue with the original payload for
      // legacy cookies.
    }
    // Unwind the codec chain in the same order it was applied during encoding.
    for (final codec in _decodeCodecs) {
      try {
        final decoded = codec.decode(name, value);

        // The encoding step stores the next payload under the `"data"` key.
        if (decoded.containsKey('data') && decoded['data'] is String) {
          value = decoded['data'] as String;
        } else {
          // Fallback for single-codec or legacy payloads.
          value = jsonEncode(decoded);
        }
      } on Object {
        // Try the next codec in the chain
        continue;
      }
    }

    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      final session = Session(
        name: name,
        options: defaultOptions.clone(),
        id: data['id'] as String?,
        values: Map<String, dynamic>.from(data['values'] as Map),
        createdAt: DateTime.parse(data['created_at'] as String),
        lastAccessed: DateTime.parse(data['last_accessed'] as String),
      );

      if (data['is_new'] != null) session.isNew = data['is_new'] as bool;
      if (data['destroyed'] == true) session.destroy();

      return session;
    } on Object {
      return Session(name: name, options: defaultOptions.clone());
    }
  }

  /// Serializes [session], protects it with the primary codec, and sets it on
  /// [response]. Destroyed sessions receive an empty, immediately expired
  /// cookie.
  @override
  Future<void> write(
    SessionRequest request,
    SessionResponse response,
    Session session,
  ) async {
    if (session.isDestroyed) {
      response.setCookie(
        session.name,
        '',
        maxAge: 0,
        path: session.options.path ?? defaultOptions.path ?? '/',
        domain: session.options.domain ?? defaultOptions.domain ?? '',
      );
      return;
    }

    final sessionData = session.toMap();

    var encoded = jsonEncode(sessionData);
    encoded = _primaryCodec.encode(session.name, {'data': encoded});
    final serialized = Uri.encodeComponent(encoded);

    response.setCookie(
      session.name,
      serialized,
      maxAge: session.options.maxAge ?? defaultOptions.maxAge,
      path: session.options.path ?? defaultOptions.path ?? '/',
      domain: session.options.domain ?? defaultOptions.domain ?? '',
      secure: session.options.secure ?? defaultOptions.secure ?? false,
      httpOnly: session.options.httpOnly ?? defaultOptions.httpOnly ?? true,
      sameSite: session.options.sameSite ?? defaultOptions.sameSite,
    );
  }

  List<SecureCookie> get _decodeCodecs => [_primaryCodec, ..._fallbackCodecs];
}
