import 'package:ormed/migrations.dart';

/// Creates the user table used by the OpenAPI example.
final class CreateUsersTable extends Migration {
  const CreateUsersTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('users', (table) {
      table
        ..increments('id')
        ..string('name')
        ..string('email')
        ..timestampsTz();
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('users', ifExists: true);
  }
}

final List<MigrationEntry> appMigrations = <MigrationEntry>[
  MigrationEntry.named(
    'm_20260908000200_create_openapi_users',
    const CreateUsersTable(),
  ),
];
