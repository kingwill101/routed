import 'package:routed/src/sessions/options.dart';

/// A simple Dart Session, analogous to Gorilla's Session struct.
/// It holds a generic map of values plus some metadata.
class Session {
  /// The name of the session.
  final String name;

  /// A map that holds the session values. The keys are strings and the values can be of any type.
  final Map<String, dynamic> values;

  /// A boolean flag indicating whether the session is new.
  bool isNew;

  /// Options for the session, encapsulated in an Options object.
  Options options;

  /// An optional ID for the session. This can be useful for identifying the session in different storage mechanisms.
  /// For example, in a CookieStore approach, the ID might be embedded in the cookie.
  /// In a FilesystemStore, you typically have a separate ID.
  /// We leave it nullable here.
  String? id;

  /// Constructor for the Session class.
  ///
  /// Takes the following parameters:
  /// - [name]: The name of the session.
  /// - [isNew]: A boolean indicating if the session is new.
  /// - [values]: A map of session values.
  /// - [options]: Session options.
  /// - [id]: An optional session ID.
  Session({
    required this.name,
    required this.isNew,
    required this.values,
    required this.options,
    this.id,
  });

  /// Retrieves and removes flash messages from the session.
  ///
  /// Flash messages are temporary messages that are typically used for notifications.
  /// They are removed from the session once they are accessed.
  ///
  /// Takes an optional [key] parameter, which defaults to '_flash'.
  /// Returns a list of flash messages.
  List<dynamic> flashes([String key = '_flash']) {
    final raw = values.remove(key);
    if (raw is List) {
      return raw;
    }
    return [];
  }

  /// Adds a flash message to the session.
  ///
  /// Flash messages are temporary messages that are typically used for notifications.
  ///
  /// Takes a [message] parameter, which is the message to be added.
  /// Takes an optional [key] parameter, which defaults to '_flash'.
  void addFlash(dynamic message, [String key = '_flash']) {
    if (!values.containsKey(key)) {
      values[key] = <dynamic>[];
    }
    (values[key] as List).add(message);
  }
}
