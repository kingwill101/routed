import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:server_contracts/server_contracts.dart' as contracts;
import 'package:server_sessions/src/options.dart';
import 'package:server_sessions/src/secure_cookie.dart';
import 'package:server_sessions/src/session.dart';
import 'package:server_sessions/src/store.dart';

/// Stores session payloads in a cache repository while persisting only a
/// lightweight identifier in the client cookie.
class CacheSessionStore implements SessionStore {
  /// Creates a cache-backed store with [repository] and cookie [codecs].
  ///
  /// [defaultOptions] apply to new sessions, [cachePrefix] namespaces cache
  /// keys, and [lifetime] controls the server-side entry lifetime.
  CacheSessionStore({
    required this.repository,
    required List<SecureCookie> codecs,
    required SessionOptions defaultOptions,
    this.cachePrefix = 'session:',
    Duration? lifetime,
  }) : codecs = codecs.isEmpty
           ? [SecureCookie(useEncryption: true, useSigning: true)]
           : codecs,
       defaultOptions = defaultOptions.clone(),
       lifetime = lifetime ?? const Duration(hours: 2);

  /// Repository responsible for persisting session payloads.
  final contracts.Repository repository;

  /// Codec stack used to encode/decode session cookies.
  final List<SecureCookie> codecs;

  /// Default session options applied when creating a new session.
  final SessionOptions defaultOptions;

  /// Prefix added to cache keys to avoid collisions.
  final String cachePrefix;

  /// Lifetime of a session before it expires on the server.
  final Duration lifetime;

  SessionOptions _cloneOptions() => defaultOptions.clone();

  String _cacheKey(String id) => '$cachePrefix$id';

  /// Reads the cookie identifier and loads its payload from [repository].
  ///
  /// Returns a new session when the cookie is missing, invalid, or has no
  /// corresponding cache entry.
  @override
  Future<Session> read(SessionRequest request, String name) async {
    final cookie = _resolveCookie(request, name);
    final options = _cloneOptions();

    if (cookie.value.isEmpty) {
      return Session(name: name, options: options);
    }

    final sessionId = _decodeSessionId(cookie, name);
    if (sessionId == null) {
      return Session(name: name, options: options);
    }

    final stored = await repository.get(_cacheKey(sessionId));
    if (stored is String && stored.isNotEmpty) {
      try {
        return Session.deserialize(stored)..isNew = false;
      } on Object catch (_) {
        // Fall through to new session if payload is corrupted.
      }
    }

    final session = Session(name: name, options: options)
      ..id = sessionId
      ..isNew = false;
    return session;
  }

  /// Stores [session] in [repository] and updates the response cookie.
  ///
  /// Rotating or destroying a session also removes the record referenced by
  /// [Session.previousId].
  @override
  Future<void> write(
    SessionRequest request,
    SessionResponse response,
    Session session,
  ) async {
    final maxAgeSeconds =
        session.options.maxAge ?? defaultOptions.maxAge ?? lifetime.inSeconds;

    if (session.isDestroyed || maxAgeSeconds <= 0) {
      await repository.forget(_cacheKey(session.id));
      // Destroy deletes by the ID referenced by the old cookie; retain support
      // for the pre-replacement ID recorded by [Session.destroy] or
      // [Session.regenerate].
      final previous = session.previousId;
      if (previous != null && previous != session.id) {
        await repository.forget(_cacheKey(previous));
      }
      response.setCookie(
        session.name,
        '',
        maxAge: 0,
        path: session.options.path ?? defaultOptions.path ?? '/',
        domain: session.options.domain ?? defaultOptions.domain ?? '',
      );
      return;
    }

    // ID rotation must invalidate the record the old cookie still references;
    // otherwise replaying the old cookie restores the pre-regeneration session.
    final previous = session.previousId;
    if (previous != null && previous != session.id) {
      await repository.forget(_cacheKey(previous));
    }

    final serialized = session.serialize();
    await repository.put(
      _cacheKey(session.id),
      serialized,
      Duration(seconds: maxAgeSeconds),
    );

    final payload = {'id': session.id};
    final encoded = codecs.first.encode(session.name, payload);
    final cookieValue = Uri.encodeComponent(encoded);

    response.setCookie(
      session.name,
      cookieValue,
      maxAge: session.options.maxAge ?? defaultOptions.maxAge,
      path: session.options.path ?? defaultOptions.path ?? '/',
      domain: session.options.domain ?? defaultOptions.domain ?? '',
      secure: session.options.secure ?? defaultOptions.secure ?? false,
      httpOnly: session.options.httpOnly ?? defaultOptions.httpOnly ?? true,
      sameSite: session.options.sameSite ?? defaultOptions.sameSite,
    );
  }

  Cookie _resolveCookie(SessionRequest request, String name) {
    return request.cookies.firstWhere(
      (c) => c.name == name,
      orElse: () => Cookie(name, ''),
    );
  }

  String? _decodeSessionId(Cookie cookie, String name) {
    if (cookie.value.isEmpty) {
      return null;
    }

    final raw = _decodeCookieValue(cookie.value, name);
    if (raw == null) {
      return null;
    }

    try {
      if (raw.containsKey('id')) {
        return raw['id'] as String?;
      }
      if (raw.containsKey('data')) {
        final inner = raw['data'];
        if (inner is Map<String, dynamic> && inner['id'] is String) {
          return inner['id'] as String;
        }
        if (inner is String) {
          try {
            final parsed = jsonDecode(inner);
            if (parsed is Map<String, dynamic> && parsed['id'] is String) {
              return parsed['id'] as String;
            }
          } on Object catch (_) {}
        }
      }
    } on Object catch (_) {
      // ignore malformed payload
    }
    return null;
  }

  Map<String, dynamic>? _decodeCookieValue(String value, String name) {
    final decoded = Uri.decodeComponent(value);
    for (final codec in codecs) {
      try {
        final result = codec.decode(name, decoded);
        return Map<String, dynamic>.from(result);
      } on Object catch (_) {
        // Try next codec
      }
    }
    return null;
  }
}
