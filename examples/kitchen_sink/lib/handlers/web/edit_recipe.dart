import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/view_models.dart';
import 'package:routed/routed.dart';

Future<Response> editRecipe(EngineContext ctx) async {
  final id = ctx.param('id');
  try {
    final recipeIndex = recipes.indexWhere((r) => r.id == id);
    if (recipeIndex == -1) {
      return ctx.string('Recipe not found', statusCode: HttpStatus.notFound);
    }

    final recipe = recipes[recipeIndex];
    final base = buildViewData(ctx, {
      'page': {'title': 'Edit ${recipe.name}', 'heading': 'Edit Recipe'},
    });

    final recipeData = recipeView(ctx, recipe);
    final routes = base['routes'] as Map<String, String>;

    final oldValues = Map<String, String>.from(
      base['old'] as Map? ?? const <String, String>{},
    );

    final formDefaults = <String, String>{
      'id': recipeData['id'] as String,
      'name': recipeData['name'] as String,
      'description': recipeData['description'] as String? ?? '',
      'ingredients': recipeData['ingredients'] as String? ?? '',
      'instructions': recipeData['instructions'] as String? ?? '',
      'prepTime': recipeData['prepTime'].toString(),
      'cookTime': recipeData['cookTime'].toString(),
      'category': recipeData['category'] as String? ?? 'breakfast',
    };

    final formValues = {...formDefaults, ...oldValues};

    return await ctx.template(
      templateName: "edit_recipe.html",
      data: {
        ...base,
        'recipe': recipeData,
        'form': {
          'heading': 'Update Recipe',
          'action': routes['save'],
          'method': 'POST',
          'submit_label': 'Update Recipe',
          'values': formValues,
          'show_cancel': true,
          'cancel_url': routes['home'],
        },
      },
    );
  } catch (e) {
    return ctx.string(
      'Error: \${e.toString()}',
      statusCode: HttpStatus.badRequest,
    );
  }
}
