part of 'server_boot.dart';

/// Returns whether [request] advertises gzip support via `Accept-Encoding`.
///
/// This parser honors quality values (`q=`) and treats `gzip;q=0` as disabled.
bool _acceptsGzip(HttpRequest request) {
  final values = <String>[];
  request.headers.forEach((name, headerValues) {
    if (_equalsAsciiIgnoreCase(name, HttpHeaders.acceptEncodingHeader)) {
      values.addAll(headerValues);
    }
  });
  if (values.isEmpty) {
    return false;
  }
  for (final value in values) {
    final parts = value.split(',');
    for (final part in parts) {
      final token = part.trim();
      if (token.isEmpty) {
        continue;
      }
      final semicolonIndex = token.indexOf(';');
      final encoding = semicolonIndex == -1
          ? token
          : token.substring(0, semicolonIndex).trim();
      if (!_equalsAsciiIgnoreCase(encoding, 'gzip')) {
        continue;
      }
      if (semicolonIndex == -1) {
        return true;
      }
      final parameters = token.substring(semicolonIndex + 1).split(';');
      var qValue = 1.0;
      for (final rawParameter in parameters) {
        final parameter = rawParameter.trim();
        if (parameter.isEmpty) {
          continue;
        }
        final equalsIndex = parameter.indexOf('=');
        if (equalsIndex == -1) {
          continue;
        }
        final name = parameter.substring(0, equalsIndex).trim();
        if (!_equalsAsciiIgnoreCase(name, 'q')) {
          continue;
        }
        qValue =
            double.tryParse(parameter.substring(equalsIndex + 1).trim()) ?? 1.0;
      }
      if (qValue > 0) {
        return true;
      }
    }
  }
  return false;
}

/// In-memory HTTP session store used by [NativeHttpServer].
///
/// Sessions are keyed by `DARTSESSID` and mirrored back to response cookies.
final class _NativeSessionStore {
  _NativeSessionStore({required Duration timeout}) : _timeout = timeout;

  static const String cookieName = 'DARTSESSID';

  final Map<String, _NativeSession> _sessions = <String, _NativeSession>{};
  Duration _timeout;
  int _nextId = 0;

  /// Updates the timeout on existing sessions and future sessions.
  void setTimeout(Duration timeout) {
    _timeout = timeout;
    for (final session in _sessions.values) {
      session.timeout = timeout;
    }
  }

  /// Resolves a session for [request], creating one when absent/expired.
  HttpSession resolve({
    required BridgeHttpRequest request,
    required HttpResponse response,
    required Duration timeout,
  }) {
    if (_timeout != timeout) {
      setTimeout(timeout);
    }
    _pruneExpiredSessions();
    final cookieValue = _sessionCookieValue(request.cookies);
    _NativeSession? session;
    if (cookieValue != null) {
      session = _sessions[cookieValue];
    }
    if (session == null) {
      session = _createSession();
      _sessions[session.id] = session;
    } else {
      session.isNew = false;
      session.touch();
    }
    session.bindResponseCookie(
      response,
      secure: request.requestedUri.scheme == 'https',
    );
    return session;
  }

  /// Cancels all timers and clears the backing store.
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }

  _NativeSession _createSession() {
    final id = _nextSessionId();
    final session = _NativeSession(
      id: id,
      timeout: _timeout,
      onExpired: () {
        _sessions.remove(id);
      },
      onDestroyed: () {
        _sessions.remove(id);
      },
    );
    return session;
  }

  String _nextSessionId() {
    _nextId++;
    final micros = DateTime.now().microsecondsSinceEpoch;
    return '$micros-$_nextId';
  }

  String? _sessionCookieValue(List<Cookie> cookies) {
    for (final cookie in cookies) {
      if (_equalsAsciiIgnoreCase(cookie.name, cookieName)) {
        return cookie.value;
      }
    }
    return null;
  }

  /// Removes expired sessions before each lookup.
  void _pruneExpiredSessions() {
    if (_sessions.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final expiredIds = <String>[];
    _sessions.forEach((id, session) {
      if (session.expiresAt.isBefore(now)) {
        expiredIds.add(id);
      }
    });
    for (final id in expiredIds) {
      final session = _sessions.remove(id);
      session?.expire();
    }
  }
}

/// Concrete mutable implementation of [HttpSession] for [NativeHttpServer].
final class _NativeSession extends MapBase<dynamic, dynamic>
    implements HttpSession {
  _NativeSession({
    required this.id,
    required Duration timeout,
    required void Function() onExpired,
    required void Function() onDestroyed,
  }) : _timeout = timeout,
       _onExpired = onExpired,
       _onDestroyed = onDestroyed {
    _scheduleTimeout();
  }

  @override
  final String id;

  @override
  bool isNew = true;

  final Map<String, dynamic> _data = <String, dynamic>{};
  final void Function() _onExpired;
  final void Function() _onDestroyed;
  final Set<HttpResponse> _boundResponses = <HttpResponse>{};
  void Function()? _timeoutCallback;

  Timer? _timer;
  bool _destroyed = false;
  Duration _timeout;
  DateTime _expiresAt = DateTime.now();

  /// Absolute expiration instant used by periodic store pruning.
  DateTime get expiresAt => _expiresAt;

  set timeout(Duration value) {
    _timeout = value;
    if (!_destroyed) {
      _scheduleTimeout();
    }
  }

  @override
  set onTimeout(void Function() callback) {
    _timeoutCallback = callback;
  }

  /// Refreshes the inactivity timer.
  void touch() {
    if (_destroyed) {
      return;
    }
    _scheduleTimeout();
  }

  /// Emits/refreshes the session cookie on [response].
  void bindResponseCookie(HttpResponse response, {required bool secure}) {
    if (_destroyed) {
      _appendExpiredSessionCookie(response, secure: secure);
      return;
    }
    _boundResponses.add(response);
    response.cookies.add(
      Cookie(_NativeSessionStore.cookieName, id)
        ..path = '/'
        ..httpOnly = true
        ..secure = secure
        ..maxAge = _timeout.inSeconds,
    );
  }

  /// Expires the session due to timeout.
  void expire() {
    if (_destroyed) {
      return;
    }
    _destroyed = true;
    _timer?.cancel();
    _timer = null;
    _data.clear();
    _timeoutCallback?.call();
    for (final response in _boundResponses) {
      _appendExpiredSessionCookie(response, secure: false);
    }
    _boundResponses.clear();
    _onExpired();
  }

  /// Releases resources without publishing cookie changes.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void destroy() {
    if (_destroyed) {
      return;
    }
    _destroyed = true;
    _timer?.cancel();
    _timer = null;
    _data.clear();
    for (final response in _boundResponses) {
      _appendExpiredSessionCookie(response, secure: false);
    }
    _boundResponses.clear();
    _onDestroyed();
  }

  @override
  dynamic operator [](Object? key) => key is String ? _data[key] : null;

  @override
  void operator []=(Object? key, dynamic value) {
    if (_destroyed) {
      throw StateError('Session is destroyed');
    }
    if (key is! String) {
      throw ArgumentError('Session keys must be strings');
    }
    _data[key] = value;
  }

  @override
  void clear() => _data.clear();

  @override
  Iterable<dynamic> get keys => _data.keys;

  @override
  dynamic remove(Object? key) => key is String ? _data.remove(key) : null;

  /// Resets timer and recomputes [expiresAt].
  void _scheduleTimeout() {
    _expiresAt = DateTime.now().add(_timeout);
    _timer?.cancel();
    if (_timeout <= Duration.zero) {
      _timer = Timer(Duration.zero, expire);
      return;
    }
    _timer = Timer(_timeout, expire);
  }

  /// Writes a clearing cookie so clients drop the expired session id.
  void _appendExpiredSessionCookie(
    HttpResponse response, {
    required bool secure,
  }) {
    response.cookies.add(
      Cookie(_NativeSessionStore.cookieName, '')
        ..path = '/'
        ..httpOnly = true
        ..secure = secure
        ..maxAge = 0
        ..expires = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
