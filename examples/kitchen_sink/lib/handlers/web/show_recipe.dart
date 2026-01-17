import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:kitchen_sink_example/view_models.dart';
import 'package:routed/routed.dart';

Future<Object> showRecipe(EngineContext ctx) async {
  final id = ctx.mustGetParam('id');
  final recipe = RecipeService.getById(id);

  if (recipe == null) {
    return ctx.string('Recipe not found', statusCode: HttpStatus.notFound);
  }

  final base = buildViewData(ctx, {
    'page': {'title': recipe.name, 'heading': recipe.name},
  });

  return await ctx.template(
    templateName: 'show_recipe.html',
    data: {...base, 'recipe': recipeView(ctx, recipe)},
  );
}
