import 'dart:async';
import 'dart:io';

import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/sessions/options.dart';
import 'package:routed/src/sessions/secure_cookie.dart';
import 'package:routed/src/sessions/session.dart';
import 'package:routed/src/sessions/store.dart';

class _MemorySession {
  _MemorySession(this.payload, this.expiresAt);

  final String payload;
  DateTime expiresAt;
}

/// In-memory, process-local session store mirroring Laravel's `array` driver.
class MemorySessionStore implements Store {
  MemorySessionStore({
    required List<SecureCookie> codecs,
    required Options defaultOptions,
    Duration? lifetime,
  }) : codecs = codecs.isEmpty
           ? [SecureCookie(useEncryption: true, useSigning: true)]
           : codecs,
       defaultOptions = defaultOptions.clone(),
       lifetime = lifetime ?? const Duration(hours: 2);

  final Map<String, _MemorySession> _sessions = {};
  final List<SecureCookie> codecs;
  final Options defaultOptions;
  final Duration lifetime;

  Options _cloneOptions() => defaultOptions.clone();

  @override
  Future<Session> read(Request request, String name) async {
    final cookie = _resolveCookie(request, name);
    final options = _cloneOptions();
    _purgeExpired();

    if (cookie.value.isEmpty) {
      return Session(name: name, options: options);
    }

    final sessionId = _decodeSessionId(cookie, name);
    if (sessionId == null) {
      return Session(name: name, options: options);
    }

    final stored = _sessions[sessionId];
    if (stored == null) {
      final session = Session(name: name, options: options)..id = sessionId;
      session.isNew = false;
      return session;
    }

    try {
      final session = Session.deserialize(stored.payload)..isNew = false;
      return session;
    } catch (_) {
      final session = Session(name: name, options: options)..id = sessionId;
      session.isNew = false;
      return session;
    }
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
      _sessions.remove(session.id);
      response.setCookie(
        session.name,
        '',
        maxAge: 0,
        path: session.options.path ?? defaultOptions.path ?? '/',
        domain: session.options.domain ?? defaultOptions.domain ?? '',
      );
      return;
    }

    final payload = session.serialize();
    final expiresAt = DateTime.now().add(Duration(seconds: maxAgeSeconds));
    _sessions[session.id] = _MemorySession(payload, expiresAt);

    final encoded = codecs.first.encode(session.name, {'id': session.id});
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

    final decoded = Uri.decodeComponent(cookie.value);
    for (final codec in codecs) {
      try {
        final payload = codec.decode(name, decoded);
        if (payload.containsKey('id')) {
          return payload['id'] as String?;
        }
      } catch (_) {
        // try next codec
      }
    }
    return null;
  }

  void _purgeExpired() {
    if (_sessions.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final expired = _sessions.entries.where(
      (entry) => entry.value.expiresAt.isBefore(now),
    );
    for (final entry in expired.toList()) {
      _sessions.remove(entry.key);
    }
  }
}
