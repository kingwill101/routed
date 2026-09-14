import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

Future<Response> homePage(EngineContext ctx) async {
  final allRecipes = (await RecipeService.getAll())
      .map((r) => r.toJson())
      .toList();

  return await ctx.view("index.html", data: {'recipes': allRecipes});
}
