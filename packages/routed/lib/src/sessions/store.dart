import 'dart:async';
import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/sessions/session.dart';

/// The `Store` abstract class defines the interface for session management.
/// Implementations are responsible for loading, creating, and saving sessions,
/// with optional support for encryption and signing of session data.
///
/// When encryption is enabled, session data is encrypted before storage.
/// When signing is enabled, session data is signed to prevent tampering.

abstract class Store {
  /// Loads an existing session or creates a new one if it does not exist.
  ///
  /// This method is analogous to Gorilla's `Store.Get` or `Store.New` methods.
  /// It takes an `Request` object and a session `name` as parameters.
  /// The `Request` object provides the context for the session, including
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
  FutureOr<Session> read(Request request, String name);

  /// Saves the session to the underlying storage mechanism.
  ///
  /// This method is responsible for persisting the session data. The storage
  /// mechanism could be a cookie, a file, a database, or any other form of
  /// persistent storage. It takes three parameters: the `Request` object,
  /// the `Response` object, and the `Session` object to be saved.
  ///
  /// The `Request` object provides the context for the session, while the
  /// `Response` object allows the method to modify the response, such as
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
  FutureOr<void> write(
    Request request,
    Response response,
    Session session,
  );
}
