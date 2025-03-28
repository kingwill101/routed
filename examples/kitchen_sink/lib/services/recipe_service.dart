import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/models/recipe.dart';

class RecipeService {
  static List<Recipe> getPaginatedRecipes(int offset, int limit) {
    return recipes.skip(offset).take(limit).toList();
  }

  static Recipe? getById(String id) {
    return recipes.firstWhere((r) => r.id == id);
  }

  static Recipe create(Recipe recipe) {
    recipes.add(recipe);
    recipeStreamController.add(recipes);
    return recipe;
  }

  static Recipe update(String id, Recipe recipe) {
    final index = recipes.indexWhere((r) => r.id == id);
    recipes[index] = recipe;
    recipeStreamController.add(recipes);
    return recipe;
  }

  static void delete(String id) {
    recipes.removeWhere((r) => r.id == id);
    recipeStreamController.add(recipes);
  }

  static List<Recipe> getAll() {
    return List.unmodifiable(recipes);
  }
}
