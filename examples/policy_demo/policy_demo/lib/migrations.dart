import 'package:ormed/migrations.dart';

/// Creates the policy resources used by the authorization example.
final class CreateProjectsTable extends Migration {
  const CreateProjectsTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('projects', (table) {
      table
        ..increments('id')
        ..string('name')
        ..string('owner_id');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('projects', ifExists: true);
  }
}

final appMigrations = <MigrationEntry>[
  MigrationEntry.named(
    'm_20260908000100_create_policy_projects',
    const CreateProjectsTable(),
  ),
];
