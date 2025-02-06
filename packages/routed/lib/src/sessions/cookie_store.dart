import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/sessions/sessions.dart';

/// Serializes a session to a Map that can be safely JSON encoded
Map<String, dynamic> _serializeSession(Session session) {
  return {
    'id': session.id,
    'values': session.values,
    'created_at': session.createdAt.toIso8601String(),
    'last_accessed': session.lastAccessed.toIso8601String(),
    'is_new': session.isNew,
    'destroyed': session.isDestroyed,
  };
}

class CookieStore implements Store {
  final List<SecureCookie> codecs;
  final Options defaultOptions;

  CookieStore({
    required this.codecs,
    Options? defaultOptions,
  }) : defaultOptions = defaultOptions ??
            Options(
              path: '/',
              domain: null,
              maxAge: 86400,
              secure: true,
              httpOnly: true,
              sameSite: 'lax',
            );

  @override
  Future<Session> read(Request request, String name) async {
    final cookie = request.cookies.firstWhere(
      (c) => c.name == name,
      orElse: () => Cookie(name, ''),
    );

    print('Reading cookie: ${cookie.name}=${cookie.value}');

    if (cookie.value.isEmpty) {
      return Session(
        name: name,
        options: defaultOptions,
      );
    }

    var value = cookie.value;
    for (final codec in codecs) {
      try {
        final decoded = codec.decode(name, value);
        value = jsonEncode(decoded);
      } catch (e) {
        continue;
      }
    }

    try {
      final Map<String, dynamic> data =
          jsonDecode(value) as Map<String, dynamic>;
      final session = Session(
        name: name,
        options: defaultOptions,
        id: data['id'] as String?,
        values: Map<String, dynamic>.from(data['values'] as Map),
        createdAt: DateTime.parse(data['created_at'] as String),
        lastAccessed: DateTime.parse(data['last_accessed'] as String),
      );

      if (data['is_new'] != null) session.isNew = data['is_new'] as bool;
      if (data['destroyed'] == true) session.destroy();

      return session;
    } catch (e) {
      return Session(
        name: name,
        options: defaultOptions,
      );
    }
  }

  @override
  Future<void> write(
      Request request, Response response, Session session) async {
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

    final sessionData = _serializeSession(session);
    print("Session data before encoding: $sessionData");
    var value = '';
    for (final codec in codecs.reversed) {
      value = codec.encode(session.name, sessionData);
    }

    response.setCookie(
      session.name,
      value,
      maxAge: session.options.maxAge ?? defaultOptions.maxAge,
      path: session.options.path ?? defaultOptions.path ?? '/',
      domain: session.options.domain ?? defaultOptions.domain ?? '',
      secure: session.options.secure ?? defaultOptions.secure ?? false,
      httpOnly: session.options.httpOnly ?? defaultOptions.httpOnly ?? true,
      sameSite:
          _getSameSite(session.options.sameSite ?? defaultOptions.sameSite),
    );
  }

  SameSite _getSameSite(String? value) {
    switch (value?.toLowerCase()) {
      case 'strict':
        return SameSite.strict;
      case 'none':
        return SameSite.none;
      default:
        return SameSite.lax;
    }
  }
}
