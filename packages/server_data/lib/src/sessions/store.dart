import 'dart:async';
import 'dart:io';

import 'session.dart';

/// Request contract used by session stores.
abstract class SessionRequest {
  List<Cookie> get cookies;
  String header(String name);
}

/// Response contract used by session stores.
abstract class SessionResponse {
  void setCookie(
    String name,
    dynamic value, {
    int? maxAge,
    String path = '/',
    String domain = '',
    bool secure = false,
    bool httpOnly = false,
    SameSite? sameSite,
  });
}

/// Session storage abstraction.
abstract class SessionStore {
  /// Reads an existing session or creates a new one if it does not exist.
  FutureOr<Session> read(SessionRequest request, String name);

  /// Persists the [session] using the underlying storage backend.
  FutureOr<void> write(
    SessionRequest request,
    SessionResponse response,
    Session session,
  );
}
