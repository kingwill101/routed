import 'package:ormed/migrations.dart';

final class CreateRateLimitEntriesTable extends Migration {
  const CreateRateLimitEntriesTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('rate_limit_entries', (table) {
      table
        ..string('key').primaryKey()
        ..text('value')
        ..integer('expires_at').nullable();
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('rate_limit_entries', ifExists: true);
  }
}

final List<MigrationEntry> appMigrations = <MigrationEntry>[
  MigrationEntry.named(
    'm_20260908000500_create_rate_limit_entries',
    const CreateRateLimitEntriesTable(),
  ),
];
