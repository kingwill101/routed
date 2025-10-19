// ignore_for_file: unused_import

import 'dart:convert';

import 'package:file/local.dart';
import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/models/recipe.dart';
import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

Future<Response> getRecipe(EngineContext ctx) async {
  final id = ctx.mustGetParam('id');
  final cacheKey = '${kRecipeCacheKeyPrefix}_$id';

  // Try cache first
  final cachedJson = await ctx.getCache(cacheKey, store: 'array');
  if (cachedJson != null) {
    return ctx.json(jsonDecode(cachedJson as String));
  }

  final recipe = RecipeService.getById(id);
  if (recipe == null) {
    return ctx.string('Recipe not found', statusCode: HttpStatus.notFound);
  }

  await ctx.cache(cacheKey, jsonEncode(recipe.toJson()), 60, store: 'array');
  return ctx.json(recipe.toJson());
}
