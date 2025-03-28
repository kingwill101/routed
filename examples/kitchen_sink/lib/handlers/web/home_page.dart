import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

homePage(EngineContext ctx) async {
  final allRecipes = RecipeService.getAll().map((r) => r.toJson()).toList();
  return ctx.html("index.html", data: {
    'recipes': allRecipes,
  });
}
