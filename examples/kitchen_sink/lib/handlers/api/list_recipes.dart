// ignore_for_file: unused_import

import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/models/recipe.dart';
import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

Future<Response> listRecipes(EngineContext ctx) async {
  final currentPage = int.tryParse(ctx.query('page') ?? '') ?? 1;
  final limit = 10;
  final offset = (currentPage - 1) * limit;

  final paginatedRecipes = RecipeService.getPaginatedRecipes(offset, limit);
  return ctx.json(paginatedRecipes.map((r) => r.toJson()).toList());
}
