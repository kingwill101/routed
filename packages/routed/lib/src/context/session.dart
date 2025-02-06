part of 'context.dart';

/// Extension for session-related functionality
extension SessionMethods on EngineContext {
  /// Get the current session instance
  Session get session =>
      _session ?? (throw StateError('Session middleware not configured'));

  /// Get a session value with optional type
  FutureOr<T?> getSession<T>(String key) => session.getValue<T>(key);

  Future<void> setSession(String key, dynamic value) async {
    session.setValue(key, value);
    print("setting session value $key to $value");
    await _commitSession();
    print("session values: ${session.values}");
  }

  Future<void> regenerateSession() async {
    final oldSession = session;
    session.regenerate();
    await _commitSession();

    // Ensure old session is invalidated
    oldSession.destroy();
    await _commitSession();
  }

  /// Get a session value with a default fallback
  Future<T> getSessionOrDefault<T>(String key, T defaultValue) async {
    return await getSession<T>(key) ?? defaultValue;
  }

  /// Remove a session value
  Future<void> removeSession(String key) async {
    session.values.remove(key);
    await _commitSession();
  }

  /// Clear all session values
  Future<void> clearSession() async {
    session.values.clear();
    await _commitSession();
  }

  /// Check if session has a key
  bool hasSession(String key) => session.values.containsKey(key);

  /// Get all session data
  Map<String, dynamic> get sessionData => Map.from(session.values);

  /// Get session creation time
  DateTime get sessionCreatedAt => session.createdAt;

  /// Get session last accessed time
  DateTime get sessionLastAccessed => session.lastAccessed;

  /// Get session age in seconds
  int get sessionAge => session.age;

  /// Get session idle time in seconds
  int get sessionIdleTime => session.idleTime;

  /// Check if session is destroyed
  bool get isSessionDestroyed => session.isDestroyed;

  /// Destroy the current session
  Future<void> destroySession() async {
    session.destroy();
    await _commitSession();
  }

  /// Get the session ID
  String get sessionId => session.id;

  Future<void> _commitSession() async {
    await engineConfig.sessionConfig!.store.write(request, response, session);
  }
}
