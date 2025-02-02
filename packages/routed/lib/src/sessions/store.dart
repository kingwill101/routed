import 'dart:io';
import 'package:routed/src/sessions/session.dart';

/// The `Store` abstract class defines the interface for session management in Dart.
/// This interface is designed to be similar to Gorilla's Store interface, but it is
/// adapted to fit the idiomatic usage patterns of Dart. Implementations of this
/// interface are responsible for loading, creating, and saving sessions.

abstract class Store {
  /// Loads an existing session or creates a new one if it does not exist.
  ///
  /// This method is analogous to Gorilla's `Store.Get` or `Store.New` methods.
  /// It takes an `HttpRequest` object and a session `name` as parameters.
  /// The `HttpRequest` object provides the context for the session, including
  /// any cookies or headers that might be used to identify the session.
  /// The `name` parameter is a string that uniquely identifies the session.
  ///
  /// Returns a `Future<Session>` that completes with the loaded or newly created
  /// `Session` object.
  ///
  /// Example usage:
  /// ```dart
  /// Future<Session> session = store.getSession(request, 'session_name');
  /// ```
  Future<Session> getSession(HttpRequest request, String name);

  /// Saves the session to the underlying storage mechanism.
  ///
  /// This method is responsible for persisting the session data. The storage
  /// mechanism could be a cookie, a file, a database, or any other form of
  /// persistent storage. It takes three parameters: the `HttpRequest` object,
  /// the `HttpResponse` object, and the `Session` object to be saved.
  ///
  /// The `HttpRequest` object provides the context for the session, while the
  /// `HttpResponse` object allows the method to modify the response, such as
  /// setting cookies or headers. The `Session` object contains the session data
  /// that needs to be saved.
  ///
  /// Returns a `Future<void>` that completes when the session has been successfully
  /// saved.
  ///
  /// Example usage:
  /// ```dart
  /// await store.saveSession(request, response, session);
  /// ```
  Future<void> saveSession(
    HttpRequest request,
    HttpResponse response,
    Session session,
  );
}
