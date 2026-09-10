import 'package:ormed/migrations.dart';

/// Creates the table used by the database architecture example.
final class CreateNotesTable extends Migration {
  const CreateNotesTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('notes', (table) {
      table
        ..increments('id')
        ..string('title')
        ..string('body')
        ..timestampsTz();
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('notes', ifExists: true);
  }
}

final List<MigrationEntry> appMigrations = <MigrationEntry>[
  MigrationEntry.named(
    'm_20260907000100_create_notes',
    const CreateNotesTable(),
  ),
];
