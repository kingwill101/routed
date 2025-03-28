import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

Future<void> deleteRecipe(EngineContext ctx) async {
  // Get recipe ID from route parameters
  final id = ctx.param('id');

  try {
    // Delete the recipe
    RecipeService.delete(id);

    // Flash success message
    await ctx.flash('success', 'Recipe deleted successfully');
  } catch (e) {
    // Flash error message if deletion fails
    await ctx.flash('error', 'Failed to delete recipe');
  }

  // Redirect back to recipe list
  await ctx.redirect(route('web.recipe.home'));
}
