import 'dart:io';

import 'package:routed/src/sessions/options.dart';
import 'package:routed/src/sessions/secure_cookie.dart';
import 'package:routed/src/sessions/session.dart';
import 'package:routed/src/sessions/store.dart';

/// The CookieStore class implements the Store interface and is responsible for
/// managing session data using cookies. It adapts Gorilla's CookieStore and
/// uses SecureCookie for signing and verifying the integrity of the cookies.
class CookieStore implements Store {
  /// A list of SecureCookie codecs used for encoding and decoding cookie values.
  /// This allows for key rotation, similar to Gorilla's older/newer keys approach.
  final List<SecureCookie> codecs;

  /// Default options for the session, such as path, domain, maxAge, etc.
  final Options defaultOptions;

  /// Constructor for the CookieStore class.
  ///
  /// [codecs] is a required parameter that provides the list of SecureCookie codecs.
  /// [defaultOptions] is an optional parameter that sets the default session options.
  /// If [defaultOptions] is not provided, it defaults to an instance of Options.
  CookieStore({
    required this.codecs,
    Options? defaultOptions,
  }) : defaultOptions = defaultOptions ?? Options();

  /// Retrieves a session from the request cookies.
  ///
  /// [request] is the HttpRequest object containing the cookies.
  /// [name] is the name of the session cookie.
  ///
  /// Returns a Future that completes with a Session object.
  @override
  Future<Session> getSession(HttpRequest request, String name) async {
    // Create a new Session object with default values, marking it as new.
    final session = Session(
      name: name,
      isNew: true,
      values: {},
      options: defaultOptions,
    );

    // Check if there's a cookie with the specified name in the request.
    final cookie = request.cookies.firstWhere(
      (c) => c.name == name,
      orElse: () => Cookie(name, ''),
    );
    // If the cookie value is empty, return the new session.
    if (cookie.value.isEmpty) {
      return session;
    }

    // Attempt to decode the cookie value using each SecureCookie codec in turn.
    for (final codec in codecs) {
      try {
        // If decoding is successful, update the session values and mark it as not new.
        final decodedValues = codec.decode(name, cookie.value);
        session.values.addAll(decodedValues);
        session.isNew = false;
        break; // Stop after a successful decode.
      } catch (_) {
        // If decoding fails, try the next codec.
      }
    }
    return session;
  }

  /// Saves the session data to a cookie in the response.
  ///
  /// [request] is the HttpRequest object.
  /// [response] is the HttpResponse object where the cookie will be added.
  /// [session] is the Session object containing the session data to be saved.
  @override
  Future<void> saveSession(
      HttpRequest request, HttpResponse response, Session session) async {
    // If the session has maxAge <= 0, delete the cookie immediately.
    final maxAge = session.options.maxAge ?? 0;
    if (maxAge <= 0) {
      final expired = Cookie(session.name, '');
      expired.maxAge = -1;
      expired.path = session.options.path;

      response.cookies.add(expired);
      return;
    }

    // Otherwise, encode the session values using the first codec in the list.
    final codec = codecs.first;
    final encoded = codec.encode(session.name, session.values);

    // Create a new cookie with the encoded session values.
    final newCookie = Cookie(session.name, encoded);

    // Set the cookie options based on the session options.
    if (session.options.path.isNotEmpty) {
      newCookie.path = session.options.path;
    }
    if (session.options.domain != null) {
      newCookie.domain = session.options.domain;
    }
    if (session.options.maxAge != null) {
      newCookie.maxAge = session.options.maxAge!;
    }
    if (session.options.secure != null) {
      newCookie.secure = session.options.secure!;
    }
    if (session.options.httpOnly != null) {
      newCookie.httpOnly = session.options.httpOnly!;
    }
    // Add the cookie to the response headers.
    response.headers.add(HttpHeaders.setCookieHeader, newCookie.toString());
  }
}
