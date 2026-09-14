import 'package:ormed/ormed.dart';
import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/models/recipe.dart';

class RecipeService {
  static const _columns = <AdHocColumn>[
    AdHocColumn(
      name: 'id',
      dartType: 'String',
      columnType: 'TEXT',
      isNullable: false,
      isPrimaryKey: true,
    ),
    AdHocColumn(name: 'name', dartType: 'String', isNullable: false),
    AdHocColumn(name: 'description', dartType: 'String', isNullable: false),
    AdHocColumn(name: 'ingredients', dartType: 'String', isNullable: false),
    AdHocColumn(name: 'instructions', dartType: 'String', isNullable: false),
    AdHocColumn(name: 'prep_time', dartType: 'int', isNullable: false),
    AdHocColumn(name: 'cook_time', dartType: 'int', isNullable: false),
    AdHocColumn(name: 'category', dartType: 'String', isNullable: false),
    AdHocColumn(name: 'image', dartType: 'String', isNullable: false),
  ];

  static late OrmDatabase _database;

  static Future<void> configure(OrmDatabase database) async {
    _database = database;
    if ((await _query().limit(1).get()).isNotEmpty) return;
    await create(
      Recipe(
        category: RecipeCategory.breakfast,
        cookTime: 54,
        description: 'A quick breakfast recipe.',
        id: uuid.v4(),
        image: '',
        ingredients: ['eggs', 'toast'],
        instructions: 'Cook and serve.',
        name: 'Simple Breakfast',
        prepTime: 11,
      ),
    );
  }

  static Future<List<Recipe>> getPaginatedRecipes(int offset, int limit) async {
    final rows = await _query().orderBy('id').offset(offset).limit(limit).get();
    return rows.map(Recipe.fromRow).toList();
  }

  static Future<Recipe?> getById(String id) async {
    final rows = await _query().whereEquals('id', id).limit(1).get();
    return rows.isEmpty ? null : Recipe.fromRow(rows.first);
  }

  static Future<Recipe> create(Recipe recipe) async {
    await _query().insertManyInputs([recipe.toStorage()], returning: false);
    await _publish();
    return recipe;
  }

  static Future<Recipe> update(String id, Recipe recipe) async {
    if (await getById(id) == null) {
      throw StateError('Recipe not found');
    }
    await _query().whereEquals('id', id).update(recipe.toStorage());
    await _publish();
    return recipe;
  }

  static Future<bool> delete(String id) async {
    final deleted = await _query().whereEquals('id', id).delete();
    if (deleted > 0) await _publish();
    return deleted > 0;
  }

  static Future<List<Recipe>> getAll() async {
    final rows = await _query().orderBy('id').get();
    return rows.map(Recipe.fromRow).toList(growable: false);
  }

  static Query<AdHocRow> _query() =>
      _database.table('recipes', columns: _columns);

  static Future<void> _publish() async {
    recipeStreamController.add(await getAll());
  }
}
