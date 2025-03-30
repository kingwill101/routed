part of 'context.dart';

/// Extension for session-related functionality
extension SessionMethods on EngineContext {
  /// Get the current session instance
  Session get session {
    if (_session == null) {
      throw StateError('Session middleware not configured');
    }
    return _session!;
  }

  /// Get a session value with optional type
  T? getSession<T>(String key) => session.getValue<T>(key);

  Future<void> setSession(String key, dynamic value) async {
    if (_session == null) {
      throw StateError('Session middleware not configured');
    }
    session.setValue(key, value);
    await _commitSession();
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
  T getSessionOrDefault<T>(String key, T defaultValue) {
    return getSession<T>(key) ?? defaultValue;
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

/// Flask-style flash message implementation
extension FlashMessages on EngineContext {
  static const String _flashKey = '_flashes';

  /// Add a flash message to the session
  Future<void> flash(String message, [String category = 'message']) async {
    try {
      // Get existing flashes, defaulting to empty list
      final List<dynamic> flashes = getSession(_flashKey) ?? <List<dynamic>>[];
      flashes.add([category, message]);

      // Store back in session
      await setSession(_flashKey, flashes);
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
          ? flashesRaw.map((flash) => flash is List ? flash : <dynamic>[]).toList()
          : <List<dynamic>>[];

      removeSession(_flashKey);

      // Apply category filter if provided
      var filteredFlashes = categoryFilter.isEmpty
          ? flashes
          : flashes.where((f) => f.isNotEmpty && f[0] is String && categoryFilter.contains(f[0])).toList();

      // Return either just messages or category-message pairs
      return withCategories
          ? filteredFlashes
          : filteredFlashes.map((f) => f.length > 1 ? f[1] : null).where((m) => m != null).toList();
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
