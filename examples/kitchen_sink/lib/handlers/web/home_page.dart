import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:kitchen_sink_example/view_models.dart';
import 'package:routed/routed.dart';

Future<Response> homePage(EngineContext ctx) async {
  final base = buildViewData(ctx, {
    'page': {'title': 'Recipes', 'heading': 'Recipes'},
  });

  final recipes = RecipeService.getAll()
      .map((recipe) => recipeView(ctx, recipe))
      .toList(growable: false);

  final oldValues = Map<String, String>.from(
    base['old'] as Map? ?? const <String, String>{},
  );

  final formDefaults = <String, String>{
    'id': '',
    'name': '',
    'description': '',
    'ingredients': '',
    'instructions': '',
    'prepTime': '',
    'cookTime': '',
    'category': 'breakfast',
  };

  final formValues = {...formDefaults, ...oldValues};

  final routes = base['routes'] as Map<String, String>;

  return await ctx.template(
    templateName: "index.html",
    data: {
      ...base,
      'recipes': recipes,
      'form': {
        'heading': 'Add New Recipe',
        'action': routes['save'],
        'method': 'POST',
        'submit_label': 'Save Recipe',
        'values': formValues,
        'show_cancel': false,
      },
    },
  );
}
