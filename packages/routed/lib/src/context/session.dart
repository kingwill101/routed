part of 'context.dart';

/// Extension for session-related functionality
extension SessionMethods on EngineContext {
  /// Get the current session instance (provided by sessionMiddleware via ctx.set('session', ...))
  Session get session {
    final s = get<Session>('session');
    if (s == null) {
      throw StateError('Session middleware not configured');
    }
    return s;
  }

  /// Get a session value with optional type
  T? getSession<T>(String key) => session.getValue<T>(key);

  void setSession(String key, dynamic value) {
    session.setValue(key, value);
  }

  void regenerateSession() {
    final oldSession = session;
    // Create a new session with a new ID but keep the same data
    final newSession = Session(
      name: oldSession.name,
      options: oldSession.options,
      values: Map<String, dynamic>.from(oldSession.values),
    );
    // Replace the old session with the new one in the context
    set('session', newSession);
    // Destroy the old session
    oldSession.destroy();
  }

  /// Get a session value with a default fallback
  T getSessionOrDefault<T>(String key, T defaultValue) {
    return getSession<T>(key) ?? defaultValue;
  }

  /// Remove a session value
  void removeSession(String key) {
    session.values.remove(key);
  }

  /// Clear all session values
  void clearSession() {
    session.values.clear();
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
  void destroySession() {
    session.destroy();
  }

  /// Get the session ID
  String get sessionId => session.id;
}

/// Flask-style flash message implementation
extension FlashMessages on EngineContext {
  static const String _flashKey = '_flashes';

  /// Add a flash message to the session
  void flash(String message, [String category = 'message']) {
    try {
      final List<dynamic> flashes = getSession(_flashKey) ?? <List<dynamic>>[];
      flashes.add([category, message]);
      setSession(_flashKey, flashes);
    } catch (e) {
      print('Error setting flash message: $e');
      rethrow;
    }
  }

  /// Get and remove flash messages from the session
  ///
  /// [withCategories] - If true, returns list of (category, message) tuples
  /// [categoryFilter] - Optional list of categories to filter messages
  List<dynamic> getFlashMessages({
    bool withCategories = false,
    List<String> categoryFilter = const [],
  }) {
    try {
      // Get and immediately remove flashes from session
      final dynamic flashesRaw = getSession<dynamic>(_flashKey);
      final List<List<dynamic>> flashes = (flashesRaw is List)
          ? flashesRaw
                .map((flash) => flash is List ? flash : <dynamic>[])
                .toList()
          : <List<dynamic>>[];

      removeSession(_flashKey);

      // Apply category filter if provided
      var filteredFlashes = categoryFilter.isEmpty
          ? flashes
          : flashes
                .where(
                  (f) =>
                      f.isNotEmpty &&
                      f[0] is String &&
                      categoryFilter.contains(f[0]),
                )
                .toList();

      // Return either just messages or category-message pairs
      return withCategories
          ? filteredFlashes
          : filteredFlashes
                .map((f) => f.length > 1 ? f[1] : null)
                .where((m) => m != null)
                .toList();
    } catch (e) {
      print('Error retrieving flash messages: $e');
      return [];
    }
  }

  /// Check if there are any flash messages
  bool hasFlashMessages() {
    final flashes = getSession<List<dynamic>>(_flashKey);
    return flashes != null && flashes.isNotEmpty;
  }
}
