import 'package:ormed_sqlite/ormed_sqlite.dart';
import 'package:routed_database/routed_database.dart';

/// Creates the default application database manager.
///
/// This starter uses a local SQLite file so it works without code generation.
/// For Cloudflare Workers, replace this factory with openCloudflareD1 from
/// package:routed_node/cloudflare.dart in an environment-aware engine.
DatabaseManager createDatabaseManager() {
  return DatabaseManager()..registerFactory(
    'default',
    () => SqliteDatabase.connect(path: 'storage/app.sqlite'),
  );
}

/// Migrations owned by the generated application.
final List<MigrationEntry> appMigrations =
    List<MigrationEntry>.unmodifiable(<MigrationEntry>[
      MigrationEntry.named(
        'm_20260829000100_create_app_metadata',
        const CreateAppMetadataTable(),
      ),
    ]);

final class CreateAppMetadataTable extends Migration {
  const CreateAppMetadataTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('app_metadata', (table) {
      table
        ..increments('id')
        ..string('key');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('app_metadata', ifExists: true);
  }
}
