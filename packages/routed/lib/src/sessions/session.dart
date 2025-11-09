import 'dart:convert';
import 'dart:math';

import 'package:routed/src/sessions/options.dart';

/// Represents a session with a unique ID and associated data.
class Session {
  /// The unique identifier for this session.
  String _id;
  set id(String value) => _id = value;

  /// Name of the session cookie
  final String name;

  /// The session options
  final Options options;

  /// Map containing the session data.
  final Map<String, dynamic> values;

  /// When the session was created.
  final DateTime _createdAt;

  /// When the session was last accessed.
  DateTime _lastAccessed;

  /// Whether the session has been destroyed.
  bool _destroyed = false;

  /// Whether this is a new session
  bool _isNew = true;

  /// Creates a new session with the given [id] and optionally [values].
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

  /// Serializes the session to a JSON string.
  String serialize() => jsonEncode(toMap());

  /// Creates a session from a JSON string.
  static Session deserialize(String data) {
    final Map<String, dynamic> map = jsonDecode(data) as Map<String, dynamic>;
    return Session(
        id: map['id'] as String?,
        name: map['name'] as String,
        options: Options.fromJson(map['options'] as Map<String, dynamic>),
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

  /// Updates the last accessed time to now.
  void touch() {
    _lastAccessed = DateTime.now();
    _isNew = false; // Mark as not new after first access
  }

  /// Marks the session as destroyed and clears all values.
  void destroy() {
    _destroyed = true;
    values.clear();
    _id = _generateId(); // Reset ID
    _lastAccessed = DateTime.now(); // Update last accessed
    options.setMaxAge(0); // Expire the cookie immediately
  }

  /// Regenerates the session ID while maintaining the session data.
  void regenerate() {
    _id = _generateId();
    touch();
  }

  /// The unique identifier for this session.
  // ignore: unnecessary_getters_setters
  String get id => _id;

  /// When the session was created.
  DateTime get createdAt => _createdAt;

  /// When the session was last accessed.
  DateTime get lastAccessed => _lastAccessed;

  /// Whether the session has been destroyed.
  bool get isDestroyed => _destroyed;

  /// Whether this is a new session
  // ignore: unnecessary_getters_setters
  bool get isNew => _isNew;
  set isNew(bool value) => _isNew = value;

  int get age => DateTime.now().difference(_createdAt).inSeconds;

  int get idleTime => DateTime.now().difference(_lastAccessed).inSeconds;

  /// Convert session to a map for serialization
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

  void setValue(String key, dynamic value) {
    touch(); // Update access time on writes
    values[key] = value;
  }
}
