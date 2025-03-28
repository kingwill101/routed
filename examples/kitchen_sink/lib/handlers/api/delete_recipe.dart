import 'dart:io';

import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

deleteRecipe(EngineContext ctx) {
  final id = ctx.param('id');

  try {
    RecipeService.delete(id);
    return ctx.string('Recipe deleted', statusCode: HttpStatus.noContent);
  } catch (e) {
    return ctx.string('Error deleting recipe',
        statusCode: HttpStatus.internalServerError);
  }
}
