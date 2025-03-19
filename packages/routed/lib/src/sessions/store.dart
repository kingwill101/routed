import 'dart:async';
import 'package:routed/src/request.dart';
import 'package:routed/src/response.dart';
import 'package:routed/src/sessions/session.dart';

/// The `Store` abstract class defines the interface for session storage and
/// retrieval. Implementations handle loading, creating, and saving sessions.
///
/// Stores can optionally support:
///   - Encryption: Session data is encrypted before storage for enhanced security.
///   - Signing: Session data is signed to prevent tampering, ensuring data integrity.
///
abstract class Store {
  /// Reads an existing session or creates a new one if it does not exist.
  ///
  /// This method retrieves a session associated with the given [request] and
  /// session [name]. If a session exists, it's loaded; otherwise, a new session
  /// is created.
  ///
  /// The [request] object provides context, including cookies or headers used to
  /// identify the session. The [name] parameter uniquely identifies the session.
  ///
  /// Returns a `Future<Session>` that completes with the loaded or newly created
  /// `Session` object.
  ///
  /// Example:
  /// ```dart
  /// final session = await store.read(request, 'my_session');
  /// ```
  FutureOr<Session> read(Request request, String name);

  /// Writes the session data to the underlying storage.
  ///
  /// This method persists the session data using a storage mechanism like a
  /// cookie, file, or database. It receives the [request], [response], and
  /// [session] objects.
  ///
  /// The [request] object provides context for the session. The [response]
  /// object allows modifying the outgoing response (e.g., setting cookies).
  /// The [session] object contains the data to be saved.
  ///
  /// Returns a `Future<void>` that completes when the session is successfully
  /// saved.
  ///
  /// Example:
  /// ```dart
  /// await store.write(request, response, session);
  /// ```
  FutureOr<void> write(
    Request request,
    Response response,
    Session session,
  );
}
