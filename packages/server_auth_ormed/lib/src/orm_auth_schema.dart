import 'package:ormed/ormed.dart';

/// Migration schema owned by [OrmAuthStore].
///
/// The adapter deliberately uses Ormed's ad-hoc query API instead of generated
/// models. A single records table keeps the package extensible as
/// `server_auth` adds optional stores while preserving typed store boundaries
/// in Dart.
final class OrmAuthSchema {
  /// Creates a schema with a validated table prefix.
  const OrmAuthSchema({this.tablePrefix = 'routed_auth'});

  /// Prefix applied to the records table.
  final String tablePrefix;

  /// Current migration version.
  static const int currentVersion = 1;

  /// Returns the records table name.
  String table(String suffix) {
    final prefix = tablePrefix.trim();
    final identifier = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');
    if (!identifier.hasMatch(prefix)) {
      throw ArgumentError.value(
        tablePrefix,
        'tablePrefix',
        'must start with a letter and contain only letters, digits, or _',
      );
    }
    if (!identifier.hasMatch(suffix)) {
      throw ArgumentError.value(
        suffix,
        'suffix',
        'must start with a letter and contain only letters, digits, or _',
      );
    }
    return '${prefix}_$suffix';
  }

  /// Ordered migration entries for the auth records table.
  List<MigrationEntry> get migrations {
    final prefix = tablePrefix.trim();
    final records = table('records');
    return [
      MigrationEntry.named(
        'm_20260907000001_create_${prefix}_auth_records',
        _CreateAuthRecordsMigration(records),
      ),
    ];
  }

  /// Applies pending migrations through Ormed's migration ledger.
  Future<MigrationReport> migrate(
    OrmDatabase database, {
    String ledgerTable = 'orm_migrations',
    int? limit,
  }) => database.migrate(migrations, ledgerTable: ledgerTable, limit: limit);
}

final class _CreateAuthRecordsMigration extends Migration {
  const _CreateAuthRecordsMigration(this.records);

  final String records;

  @override
  void up(SchemaBuilder builder) {
    builder.create(records, (table) {
      table.text('record_key').primaryKey();
      table.text('kind');
      table.text('lookup').nullable();
      table.text('owner_id').nullable();
      table.text('payload');
      table.text('created_at');
      table.text('expires_at').nullable();
      table.text('updated_at');
      table.unique(['kind', 'lookup']);
      table.index(['kind', 'lookup']);
      table.index(['kind', 'owner_id']);
    });
  }

  @override
  void down(SchemaBuilder builder) {
    builder.drop(records, ifExists: true);
  }
}
