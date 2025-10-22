// Application State (in-memory data)
import 'dart:async';

import 'package:file/local.dart';
import 'package:kitchen_sink_example/models/recipe.dart';
import 'package:uuid/uuid.dart';

// This was moved so uuid can be constructed.
final List<Recipe> recipes = [
  Recipe(
    category: RecipeCategory.breakfast,
    cookTime: 54,
    description: "oigyv huijuj8hybogvi khbjunyo7g9t6frcugv ibyhunyo",
    id: "80c45a97-4d6a-4ae4-aa46-e94d61d29ecd",
    image: "",
    ingredients: ["dsfsdfd", "Dfsdfsdf", "F5234y"],
    instructions:
        "gybk vhybh8oubgkh vyg y7ibgy hybgkbyh8yobugyh 8yobuohy8oybuuhbnlhuo8hkbgybi7gtvj cvkhbuyp9j8t",
    name: ";ln l;j klj j j u h9bihnkoh97gtivy hybuij",
    prepTime: 11,
  ),
];
final uuid = Uuid();
final templateFileSystem = LocalFileSystem();

// Add cache keys
const String kAllRecipesCacheKey = 'all_recipes';
const String kRecipeCacheKeyPrefix = 'recipe';
const String kRecipeCountCacheKey = 'recipe_count';
//Template Directory is added
final templateDirectory = 'templates';
StreamController recipeStreamController =
    StreamController<List<Recipe>>.broadcast();
