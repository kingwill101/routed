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

final class CreateRecipeMetadataTable extends Migration {
  const CreateRecipeMetadataTable();

  @override
  void up(SchemaBuilder schema) {
    schema.create('recipe_metadata', (table) {
      table.string('key').primaryKey();
      table.string('value');
    });
  }

  @override
  void down(SchemaBuilder schema) {
    schema.drop('recipe_metadata', ifExists: true);
  }
}

final List<MigrationEntry> appMigrations = <MigrationEntry>[
  MigrationEntry.named(
    'm_20260908000300_create_recipes',
    const CreateRecipesTable(),
  ),
  MigrationEntry.named(
    'm_20260908000301_create_recipe_metadata',
    const CreateRecipeMetadataTable(),
  ),
];
