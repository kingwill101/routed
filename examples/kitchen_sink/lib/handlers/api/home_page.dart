import 'package:kitchen_sink_example/consts.dart';
import 'package:routed/routed.dart';

Future<Response> homePage(EngineContext ctx) async {
  final allRecipes = recipes.map((r) => r.toJson()).toList();

  return await ctx.html("index.html", data: {'recipes': allRecipes});
}
