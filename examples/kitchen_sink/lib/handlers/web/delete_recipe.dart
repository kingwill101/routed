import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

Future<Response> deleteRecipe(EngineContext ctx) async {
  final id = ctx.mustGetParam('id');

  try {
    if (await RecipeService.delete(id)) {
      ctx.flash('Recipe deleted successfully.', 'success');
    } else {
      ctx.flash('Recipe not found.', 'error');
    }
  } catch (e) {
    ctx.flash('Failed to delete recipe.', 'error');
  }

  return ctx.redirect(ctx.route('web.recipe.home'));
}
