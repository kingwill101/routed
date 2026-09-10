import 'package:ormed/migrations.dart';

final class CreateProjectsTable extends Migration {
  const CreateProjectsTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('projects', (table) {
      table
        ..increments('id')
        ..string('tenant_id')
        ..string('owner_id')
        ..string('name')
        ..timestampsTz();
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('projects', ifExists: true);
  }
}

final List<MigrationEntry> appMigrations = <MigrationEntry>[
  MigrationEntry.named(
    'm_20260907000200_create_projects',
    const CreateProjectsTable(),
  ),
];
