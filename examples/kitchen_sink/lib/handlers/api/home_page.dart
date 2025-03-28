import 'package:kitchen_sink_example/consts.dart';
import 'package:routed/routed.dart';

homePage(EngineContext ctx) async {
  final allRecipes = recipes.map((r) => r.toJson()).toList();

  return ctx.html("index.html", data: {'recipes': allRecipes});
}
