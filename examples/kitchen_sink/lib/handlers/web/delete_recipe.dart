import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

Future<Response> deleteRecipe(EngineContext ctx) async {
  final id = ctx.mustGetParam('id');

  try {
    RecipeService.delete(id);
    ctx.flash('Recipe deleted successfully.', 'success');
  } catch (e) {
    ctx.flash('Failed to delete recipe.', 'error');
  }

  return ctx.redirect(route('web.recipe.home'));
}
