import 'package:routed/src/context/context.dart';
import 'package:routed/src/context/context_key.dart';
import 'package:routed/src/context/typed_context_state.dart';
import 'package:routed/src/sessions/session.dart';

const sessionKey = ContextKey<Session>('session');

extension SessionMethods on EngineContext {
  Session get session {
    final s = read(sessionKey);
    if (s == null) {
      throw StateError('Session middleware not configured');
    }
    return s;
  }
  T? getSession<T>(String key) => session.getValue<T>(key);
  void setSession(String key, dynamic value) {
    session.setValue(key, value);
  }
  void regenerateSession() {
    final oldSession = session;
    final newSession = Session(
      name: oldSession.name,
      options: oldSession.options,
      values: Map<String, dynamic>.from(oldSession.values),
    );
    (this as dynamic).write(sessionKey, newSession);
    oldSession.destroy();
  }
  T getSessionOrDefault<T>(String key, T defaultValue) {
    return getSession<T>(key) ?? defaultValue;
  }
  void removeSession(String key) {
    session.values.remove(key);
  }
  void clearSession() {
    session.values.clear();
  }
  bool hasSession(String key) => session.values.containsKey(key);
  Map<String, dynamic> get sessionData => Map.from(session.values);
  DateTime get sessionCreatedAt => session.createdAt;
  DateTime get sessionLastAccessed => session.lastAccessed;
  int get sessionAge => session.age;
  int get sessionIdleTime => session.idleTime;
  bool get isSessionDestroyed => session.isDestroyed;
  void destroySession() {
    session.destroy();
  }
  String get sessionId => session.id;
}
extension FlashMessages on EngineContext {
  static const String _flashKey = '_flashes';
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
  List<dynamic> getFlashMessages({bool withCategories = false, List<String> categoryFilter = const [],}) {
    try {
      final dynamic flashesRaw = getSession<dynamic>(_flashKey);
      final List<List<dynamic>> flashes = (flashesRaw is List) ? flashesRaw.map((flash) => flash is List ? flash : <dynamic>[]).toList() : <List<dynamic>>[];
      removeSession(_flashKey);
      var filteredFlashes = categoryFilter.isEmpty ? flashes : flashes.where((f) => f.isNotEmpty && f[0] is String && categoryFilter.contains(f[0]),).toList();
      return withCategories ? filteredFlashes : filteredFlashes.map((f) => f.length > 1 ? f[1] : null).where((m) => m != null).toList();
    } catch (e) {
      print('Error retrieving flash messages: $e');
      return [];
    }
  }
  bool hasFlashMessages() {
    final flashes = getSession<List<dynamic>>(_flashKey);
    return flashes != null && flashes.isNotEmpty;
  }
}
