import 'dart:io';

import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

showRecipe(EngineContext ctx) async {
  final id = ctx.mustGetParam('id');
  final recipe = RecipeService.getById(id);

  if (recipe == null) {
    return ctx.string('Recipe not found', statusCode: HttpStatus.notFound);
  }

  return ctx.html('show_recipe.html', data: {'recipe': recipe.toJson()});
}
