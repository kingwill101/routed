import 'dart:async';
import 'dart:io';

import 'session.dart';

/// Request contract used by session stores.
abstract class SessionRequest {
  /// Cookies received with the request.
  List<Cookie> get cookies;

  /// Returns the value of the request header named [name].
  ///
  /// Returns an empty string when the request does not contain the header.
  String header(String name);
}

/// Response contract used by session stores.
abstract class SessionResponse {
  /// Adds a response cookie named [name] with [value] and the supplied
  /// attributes.
  ///
  /// [maxAge] controls its lifetime; [path], [domain], [secure], [httpOnly],
  /// and [sameSite] are passed to the response implementation.
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
  /// Loads the session named [name], creating one when no valid cookie exists.
  ///
  /// Implementations may perform asynchronous I/O.
  FutureOr<Session> read(SessionRequest request, String name);

  /// Persists [session] and updates [response] with its cookie.
  ///
  /// Implementations may perform asynchronous I/O.
  FutureOr<void> write(
    SessionRequest request,
    SessionResponse response,
    Session session,
  );
}
