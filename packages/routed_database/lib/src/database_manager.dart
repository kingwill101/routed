import 'dart:async';

import 'package:ormed/ormed.dart';

/// Opens an Ormed database for a named connection.
typedef DatabaseFactory = FutureOr<OrmDatabase> Function();

/// Manages named Ormed database handles for a Routed application.
///
/// The manager deliberately accepts concrete [OrmDatabase] instances or
/// factories. This keeps connection creation host-specific while exposing one
/// stable application API for local SQLite, server databases, and Worker
/// bindings such as Cloudflare D1.
final class DatabaseManager {
  /// Creates a manager whose default connection is [defaultConnection].
  DatabaseManager({String defaultConnection = 'default'})
    : _defaultConnection = _normalizeName(defaultConnection);

  final Map<String, _DatabaseEntry> _entries = <String, _DatabaseEntry>{};
  String _defaultConnection;
  bool _initialized = false;
  bool _closed = false;

  /// The name used by [database] when no name is supplied.
  String get defaultConnection => _defaultConnection;

  /// Names registered with this manager.
  Iterable<String> get names => _entries.keys;

  /// Whether [name] has been registered.
  bool has(String name) => _entries.containsKey(_normalizeName(name));

  /// Registers an already-open database handle.
  ///
  /// By default the manager closes the handle during [close]. Set
  /// [closeOnDispose] to `false` when another lifecycle owns it.
  void register(
    String name,
    OrmDatabase database, {
    bool closeOnDispose = true,
  }) {
    _ensureMutable();
    final normalized = _normalizeName(name);
    _ensureUnique(normalized);
    _entries[normalized] = _DatabaseEntry.open(
      database,
      closeOnDispose: closeOnDispose,
    );
  }

  /// Registers a lazily-created database connection.
  ///
  /// The factory is invoked once during [initialize], and its result is then
  /// reused for every request handled by the engine.
  void registerFactory(
    String name,
    DatabaseFactory factory, {
    bool closeOnDispose = true,
  }) {
    _ensureMutable();
    final normalized = _normalizeName(name);
    _ensureUnique(normalized);
    _entries[normalized] = _DatabaseEntry.lazy(
      factory,
      closeOnDispose: closeOnDispose,
    );
  }

  /// Changes the default connection name.
  void setDefault(String name) {
    _ensureMutable();
    _defaultConnection = _normalizeName(name);
  }

  /// Opens all registered factories and validates the default connection.
  ///
  /// This method is idempotent and is normally called by
  /// the database provider during engine boot.
  Future<void> initialize() async {
    if (_closed) {
      throw StateError('Database manager is closed');
    }
    if (_initialized) return;
    if (_entries.isEmpty) {
      throw StateError('No databases have been registered');
    }
    final defaultEntry = _entries[_defaultConnection];
    if (defaultEntry == null) {
      throw StateError(
        'Default database "$_defaultConnection" is not registered',
      );
    }
    for (final entry in _entries.values) {
      await entry.open();
    }
    _initialized = true;
  }

  /// Returns a named database, or the default connection when omitted.
  OrmDatabase database([String? name]) {
    if (!_initialized) {
      throw StateError('Database manager has not been initialized');
    }
    if (_closed) {
      throw StateError('Database manager is closed');
    }
    final selected = _normalizeOptionalName(name) ?? _defaultConnection;
    final entry = _entries[selected];
    final database = entry?.database;
    if (database == null) {
      throw StateError('Database "$selected" is not registered');
    }
    return database;
  }

  /// Applies [entries] to a named connection and records them in Ormed's
  /// migration ledger.
  ///
  /// The manager must have been initialized first. When [connection] is
  /// omitted, the default connection is used. D1 and other remote drivers
  /// retain their own transaction/atomicity semantics; this method delegates
  /// directly to Ormed's driver-aware migration runner.
  Future<MigrationReport> migrate(
    Iterable<MigrationEntry> entries, {
    String? connection,
    String ledgerTable = 'orm_migrations',
    int? limit,
  }) {
    return database(connection).migrate(
      entries,
      ledgerTable: ledgerTable,
      limit: limit,
    );
  }

  /// Closes all manager-owned database handles.
  ///
  /// Closing is idempotent. If multiple handles fail to close, the first
  /// error is rethrown after all handles have had an opportunity to close.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final closed = Set<OrmDatabase>.identity();
    Object? firstError;
    StackTrace? firstStack;
    for (final entry in _entries.values) {
      final database = entry.database;
      if (!entry.closeOnDispose || database == null || !closed.add(database)) {
        continue;
      }
      try {
        await database.close();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }
    final error = firstError;
    final stack = firstStack;
    if (error != null && stack != null) {
      Error.throwWithStackTrace(error, stack);
    }
  }

  void _ensureMutable() {
    if (_initialized) {
      throw StateError('Databases cannot be changed after initialization');
    }
    if (_closed) {
      throw StateError('Database manager is closed');
    }
  }

  void _ensureUnique(String name) {
    if (_entries.containsKey(name)) {
      throw ArgumentError('Database "$name" is already registered');
    }
  }

  static String _normalizeName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(name, 'name', 'cannot be empty');
    }
    return normalized;
  }

  static String? _normalizeOptionalName(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    return _normalizeName(name);
  }
}

final class _DatabaseEntry {
  _DatabaseEntry.open(this.database, {required this.closeOnDispose})
    : _factory = null,
      _opening = null;

  _DatabaseEntry.lazy(this._factory, {required this.closeOnDispose})
    : database = null,
      _opening = null;

  OrmDatabase? database;
  final DatabaseFactory? _factory;
  final bool closeOnDispose;
  Future<OrmDatabase>? _opening;

  Future<OrmDatabase> open() {
    final current = database;
    if (current != null) return Future<OrmDatabase>.value(current);
    final opening = _opening ??= Future<OrmDatabase>.sync(_factory!);
    return opening.then((value) {
      database = value;
      return value;
    });
  }
}
