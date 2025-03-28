import 'dart:io';

import 'package:kitchen_sink_example/consts.dart';
import 'package:routed/routed.dart';

editRecipe(EngineContext ctx) async {
  final id = ctx.param('id');
  try {
    final recipeIndex = recipes.indexWhere((r) => r.id == id);
    if (recipeIndex == -1) {
      return ctx.string('Recipe not found', statusCode: HttpStatus.notFound);
    }

    final recipe = recipes[recipeIndex];
    ctx.html("edit_recipe.html", data: {'recipe': recipe.toJson()});
  } catch (e) {
    return ctx.string('Error: \${e.toString()}',
        statusCode: HttpStatus.badRequest);
  }
}
