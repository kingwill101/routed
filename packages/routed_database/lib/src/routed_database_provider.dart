import 'package:ormed/ormed.dart';
import 'package:routed_core/routed_core.dart';

import 'package:routed_database/src/database_manager.dart';

/// Registers a [DatabaseManager] with a Routed application.
final class RoutedDatabaseProvider extends ServiceProvider {
  /// Creates a provider for [manager].
  RoutedDatabaseProvider({
    required this.manager,
    Iterable<MigrationEntry> migrations = const <MigrationEntry>[],
    this.migrateOnBoot = false,
    this.migrationConnection,
    this.migrationLedgerTable = 'orm_migrations',
    this.migrationLimit,
  }) : migrations = List<MigrationEntry>.unmodifiable(migrations);

  /// The manager exposed to the application container.
  final DatabaseManager manager;

  /// Migration entries optionally applied during provider boot.
  final List<MigrationEntry> migrations;

  /// Whether [migrations] should be applied during provider boot.
  ///
  /// This is opt-in because production deployments commonly run migrations
  /// as a separate release step. It is useful for local development and a
  /// single-owner Worker bootstrap.
  final bool migrateOnBoot;

  /// Connection receiving [migrations], or the manager's default connection.
  final String? migrationConnection;

  /// Ormed ledger table used for [migrations].
  final String migrationLedgerTable;

  /// Optional limit on migrations applied during boot.
  final int? migrationLimit;

  MigrationReport? _lastMigrationReport;

  /// The most recent boot migration report, when migrations ran.
  MigrationReport? get lastMigrationReport => _lastMigrationReport;

  @override
  void register(Container container) {
    container.instance<DatabaseManager>(manager);
  }

  @override
  Future<void> boot(Container container) async {
    await manager.initialize();
    if (migrateOnBoot && migrations.isNotEmpty) {
      _lastMigrationReport = await manager.migrate(
        migrations,
        connection: migrationConnection,
        ledgerTable: migrationLedgerTable,
        limit: migrationLimit,
      );
    }
  }

  @override
  Future<void> cleanup(Container container) async {
    if (!container.has<Engine>()) return;
    final engine = container.get<Engine>();
    if (!identical(container, engine.container)) return;
    await manager.close();
  }
}

/// Adds [manager] to a request container when no more specific binding exists.
Middleware databaseMiddleware(DatabaseManager manager) {
  return (ctx, next) {
    if (!ctx.container.has<DatabaseManager>()) {
      ctx.container.instance<DatabaseManager>(manager);
    }
    return next();
  };
}

/// Database-manager accessors for Routed handlers.
extension DatabaseEngineContext on EngineContext {
  /// Returns the manager registered in this request's container.
  DatabaseManager get databaseManager {
    if (container.has<DatabaseManager>()) {
      return container.get<DatabaseManager>();
    }
    throw StateError('Database manager not configured');
  }

  /// Returns a named Ormed database, or the default connection.
  OrmDatabase db([String? name]) => databaseManager.database(name);

  /// Whether a database manager is available in this request.
  bool get hasDatabaseManager => container.has<DatabaseManager>();
}

/// Registers a configured provider in Routed's shared provider registry.
///
/// The manager is captured by the registered factory, so all engines resolved
/// through this registry entry use the same host-owned connections.
void registerRoutedDatabaseProviders(DatabaseManager manager) {
  ProviderRegistry.instance.register(
    'routed.database',
    factory: () => RoutedDatabaseProvider(manager: manager),
    description: 'Ormed database manager and request access.',
  );
}
