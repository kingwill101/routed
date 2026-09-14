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

final class CreateRateLimitLocksTable extends Migration {
  const CreateRateLimitLocksTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('rate_limit_locks', (table) {
      table
        ..string('name').primaryKey()
        ..string('owner')
        ..integer('expires_at').nullable();
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('rate_limit_locks', ifExists: true);
  }
}

final List<MigrationEntry> appMigrations = <MigrationEntry>[
  MigrationEntry.named(
    'm_20260908000500_create_rate_limit_entries',
    const CreateRateLimitEntriesTable(),
  ),
  MigrationEntry.named(
    'm_20260914000500_create_rate_limit_locks',
    const CreateRateLimitLocksTable(),
  ),
];
