import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:routed/src/contracts/cache/repository.dart' as cache;
import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/sessions/options.dart';
import 'package:routed/src/sessions/session.dart';
import 'package:routed/src/sessions/secure_cookie.dart';
import 'package:routed/src/sessions/store.dart';

/// Stores session payloads inside a cache repository while only persisting
/// lightweight identifiers inside the client cookie.
class CacheSessionStore implements Store {
  CacheSessionStore({
    required this.repository,
    required List<SecureCookie> codecs,
    required Options defaultOptions,
    this.cachePrefix = 'session:',
    Duration? lifetime,
  }) : codecs = codecs.isEmpty
           ? [SecureCookie(useEncryption: true, useSigning: true)]
           : codecs,
       defaultOptions = defaultOptions.clone(),
       lifetime = lifetime ?? const Duration(hours: 2);

  /// Repository responsible for persisting session payloads.
  final cache.Repository repository;

  /// Codec stack used to encode/decode session cookies.
  final List<SecureCookie> codecs;

  /// Default session options applied when creating a new session.
  final Options defaultOptions;

  /// Prefix added to cache keys to avoid collisions.
  final String cachePrefix;

  /// Lifetime of a session before it expires on the server.
  final Duration lifetime;

  Options _cloneOptions() => defaultOptions.clone();

  String _cacheKey(String id) => '$cachePrefix$id';

  @override
  Future<Session> read(Request request, String name) async {
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
      } catch (_) {
        // Fall through to new session if payload is corrupted.
      }
    }

    final session = Session(name: name, options: options)..id = sessionId;
    session.isNew = false;
    return session;
  }

  @override
  Future<void> write(
    Request request,
    Response response,
    Session session,
  ) async {
    final maxAgeSeconds =
        session.options.maxAge ?? defaultOptions.maxAge ?? lifetime.inSeconds;

    if (session.isDestroyed || maxAgeSeconds <= 0) {
      await repository.forget(_cacheKey(session.id));
      response.setCookie(
        session.name,
        '',
        maxAge: 0,
        path: session.options.path ?? defaultOptions.path ?? '/',
        domain: session.options.domain ?? defaultOptions.domain ?? '',
      );
      return;
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

  Cookie _resolveCookie(Request request, String name) {
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
          } catch (_) {}
        }
      }
    } catch (_) {
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
      } catch (_) {
        // Try next codec
      }
    }
    return null;
  }
}
