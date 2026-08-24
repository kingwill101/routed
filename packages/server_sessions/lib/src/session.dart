import 'dart:convert';
import 'dart:math';

import 'options.dart';

/// Represents a session with a unique ID and associated data.
class Session {
  String _id;

  /// The previously persisted ID, retained until the backend store has had a
  /// chance to delete it.
  ///
  /// Set when [destroy] or [regenerate] replaces [_id], so stores can remove
  /// the record still referenced by an old cookie instead of leaving it valid.
  String? _previousId;

  /// Name of the session cookie.
  final String name;

  /// Cookie attributes and lifetime applied when the session is written.
  final SessionOptions options;

  /// Map containing the session data.
  final Map<String, dynamic> values;

  /// When the session was created.
  final DateTime _createdAt;

  /// When the session was last accessed.
  DateTime _lastAccessed;

  /// Whether the session has been destroyed.
  bool _destroyed = false;

  bool _isNew = true;

  /// Creates a session with the supplied cookie [name] and [options].
  ///
  /// Generates an identifier and timestamps when [id], [createdAt], or
  /// [lastAccessed] is omitted.
  Session({
    String? id,
    required this.name,
    required this.options,
    Map<String, dynamic>? values,
    DateTime? createdAt,
    DateTime? lastAccessed,
  }) : _id = id ?? _generateId(),
       values = values ?? {},
       _createdAt = createdAt ?? DateTime.now(),
       _lastAccessed = lastAccessed ?? DateTime.now();

  /// Serializes this session to a JSON string.
  String serialize() => jsonEncode(toMap());

  /// Creates a session from a JSON string.
  ///
  /// Throws a [FormatException] or a [TypeError] when [data] does not contain
  /// the session representation produced by [serialize].
  static Session deserialize(String data) {
    final Map<String, dynamic> map = jsonDecode(data) as Map<String, dynamic>;
    return Session(
        id: map['id'] as String?,
        name: map['name'] as String,
        options: SessionOptions.fromJson(
          map['options'] as Map<String, dynamic>,
        ),
        values: Map<String, dynamic>.from(map['values'] as Map),
        createdAt: DateTime.parse(map['created_at'] as String),
        lastAccessed: DateTime.parse(map['last_accessed'] as String),
      )
      .._destroyed = map['destroyed'] as bool? ?? false
      .._isNew = map['is_new'] as bool? ?? false;
  }

  /// Generates a random session ID.
  static String _generateId() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// Updates the last-accessed time and marks this session as no longer new.
  void touch() {
    _lastAccessed = DateTime.now();
    _isNew = false; // Mark as not new after first access
  }

  /// Marks the session as destroyed and clears all values.
  ///
  /// The current persisted ID is retained in [previousId] so the backend store
  /// can delete the original record when [SessionStore.write] runs; otherwise
  /// the old cookie
  /// would keep resolving to an orphaned session until it expires.
  void destroy() {
    _destroyed = true;
    values.clear();
    _previousId ??= _id; // Retain the persisted ID for server-side deletion
    _id = _generateId(); // Reset ID
    _lastAccessed = DateTime.now(); // Update last accessed
    options.setMaxAge(0); // Expire the cookie immediately
  }

  /// Regenerates the session ID while maintaining the session data.
  ///
  /// The ID that was active before regeneration is recorded in [previousId] so
  /// the next [SessionStore.write] can invalidate the record referenced by the
  /// old cookie.
  void regenerate() {
    _previousId = _id;
    _id = _generateId();
    touch();
  }

  /// The unique identifier for this session.
  ///
  /// Assigning an identifier is intended for store implementations. Call
  /// [regenerate] when application code needs to rotate an active session ID.
  // ignore: unnecessary_getters_setters
  String get id => _id;
  set id(String value) => _id = value;

  /// The ID that was persisted before the last [destroy] or [regenerate], or
  /// null when the session ID has never been replaced.
  String? get previousId => _previousId;

  /// The time at which this session was created.
  DateTime get createdAt => _createdAt;

  /// The time at which this session was last accessed.
  DateTime get lastAccessed => _lastAccessed;

  /// Whether the session has been destroyed.
  bool get isDestroyed => _destroyed;

  /// Whether this is a new session.
  // ignore: unnecessary_getters_setters
  bool get isNew => _isNew;
  set isNew(bool value) => _isNew = value;

  /// The number of elapsed seconds since [createdAt].
  int get age => DateTime.now().difference(_createdAt).inSeconds;

  /// The number of elapsed seconds since [lastAccessed].
  int get idleTime => DateTime.now().difference(_lastAccessed).inSeconds;

  /// Converts this session to a JSON-compatible map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'options': options.toJson(),
      'values': values,
      'created_at': _createdAt.toIso8601String(),
      'last_accessed': _lastAccessed.toIso8601String(),
      'destroyed': _destroyed,
      'is_new': _isNew,
    };
  }

  /// Returns the value for [key] when it has type [T].
  ///
  /// A value is converted to a string when [T] is `String`; otherwise a type
  /// mismatch returns `null`. This method calls [touch], including when the
  /// key is missing or the value has the wrong type.
  T? getValue<T>(String key) {
    touch(); // Update access time on reads
    final value = values[key];
    if (value == null) {
      return null;
    }

    if (value is T) {
      return value;
    }

    // Handle common type conversions
    if (T == String && value != null) {
      return value.toString() as T;
    }

    // For other types, return null if type doesn't match
    return null;
  }

  /// Stores [value] under [key] and updates the last-accessed time.
  void setValue(String key, dynamic value) {
    touch(); // Update access time on writes
    values[key] = value;
  }
}
