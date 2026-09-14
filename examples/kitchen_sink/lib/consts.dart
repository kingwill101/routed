import 'dart:async';

import 'package:file/local.dart';
import 'package:kitchen_sink_example/models/recipe.dart';
import 'package:uuid/uuid.dart';

final uuid = Uuid();
final templateFileSystem = LocalFileSystem();

// Add cache keys
const String kAllRecipesCacheKey = 'all_recipes';
const String kRecipeCacheKeyPrefix = 'recipe';
const String kRecipeCountCacheKey = 'recipe_count';
//Template Directory is added
final templateDirectory = 'templates';
StreamController<List<Recipe>> recipeStreamController =
    StreamController<List<Recipe>>.broadcast();
