import 'dart:io';

import 'package:kitchen_sink_example/models/recipe.dart';
import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

class RecipeUpdateBinding {
  String? name;
  String? description;
  List<String>? ingredients;
  String? instructions;
  int? prepTime;
  int? cookTime;
  String? category;
  String? image;
}

updateRecipe(EngineContext ctx) async {
  final id = ctx.param('id');
  final existingRecipe = RecipeService.getById(id);

  if (existingRecipe == null) {
    return ctx.string('Recipe not found', statusCode: HttpStatus.notFound);
  }

  final data = RecipeUpdateBinding();
  await ctx.bind(data);

  await ctx.validate({
    'name': 'string|min:3',
    'description': 'nullable|string',
    'ingredients': 'array',
    'instructions': 'string',
    'prepTime': 'int|min:0',
    'cookTime': 'int|min:0',
    'category': 'in:${RecipeCategory.values.map((e) => e.name).join(',')}',
  }, bail: true);

  final updatedRecipe = existingRecipe.copyWith(
    name: data.name ?? existingRecipe.name,
    description: data.description ?? existingRecipe.description,
    ingredients: data.ingredients ?? existingRecipe.ingredients,
    instructions: data.instructions ?? existingRecipe.instructions,
    prepTime: data.prepTime ?? existingRecipe.prepTime,
    cookTime: data.cookTime ?? existingRecipe.cookTime,
    category: data.category != null
        ? RecipeCategory.values.byName(data.category!)
        : existingRecipe.category,
    image: data.image ?? existingRecipe.image,
  );

  final savedRecipe = RecipeService.update(id, updatedRecipe);
  return ctx.json(savedRecipe.toJson());
}
