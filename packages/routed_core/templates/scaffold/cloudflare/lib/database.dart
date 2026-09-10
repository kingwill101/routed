import 'package:routed_database/routed_database.dart';
import 'package:routed_node/cloudflare.dart';

/// Creates the D1-backed database manager for this Worker.
DatabaseManager createDatabaseManager(CloudflareEnvironment environment) {
  return DatabaseManager()..registerFactory(
    'default',
    () => openCloudflareD1(environment, binding: 'DB'),
  );
}

/// Migrations owned by the generated application.
final List<MigrationEntry> appMigrations = List<MigrationEntry>.unmodifiable(
  <MigrationEntry>[
    MigrationEntry.named(
      'm_20260829000100_create_app_metadata',
      const CreateAppMetadataTable(),
    ),
  ],
);

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
