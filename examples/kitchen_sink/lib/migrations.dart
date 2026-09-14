import 'package:ormed/migrations.dart';

final class CreateRecipesTable extends Migration {
  const CreateRecipesTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('recipes', (table) {
      table
        ..string('id').primaryKey()
        ..string('name')
        ..text('description')
        ..text('ingredients')
        ..text('instructions')
        ..integer('prep_time')
        ..integer('cook_time')
        ..string('category')
        ..string('image')
        ..timestampsTz();
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('recipes', ifExists: true);
  }
}

final List<MigrationEntry> appMigrations = <MigrationEntry>[
  MigrationEntry.named(
    'm_20260908000300_create_recipes',
    const CreateRecipesTable(),
  ),
];
