import 'package:kitchen_sink_example/models/recipe.dart';
import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

class RecipeUpdateBinding implements Bindable {
  String? name;
  String? description;
  List<String>? ingredients;
  String? instructions;
  int? prepTime;
  int? cookTime;
  String? category;
  String? image;

  @override
  void bind(Map<String, dynamic> data) {
    name = data['name']?.toString();
    description = data['description']?.toString();
    ingredients = (data['ingredients'] as List?)
        ?.map((value) => value.toString())
        .toList();
    instructions = data['instructions']?.toString();
    prepTime = _toInt(data['prepTime']);
    cookTime = _toInt(data['cookTime']);
    category = data['category']?.toString();
    image = data['image']?.toString();
  }
}

int? _toInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

Future<Response> updateRecipe(EngineContext ctx) async {
  final id = ctx.mustGetParam('id');
  final existingRecipe = RecipeService.getById(id);

  if (existingRecipe == null) {
    return ctx.string('Recipe not found', statusCode: HttpStatus.notFound);
  }

  final data = RecipeUpdateBinding();
  await BindingMethods(ctx).bind(data);

  await ValidationContext(ctx).validate({
    'name': 'string|min:3',
    'description': 'nullable|string',
    'ingredients': 'array',
    'instructions': 'string',
    'prepTime': 'int|min:0',
    'cookTime': 'int|min:0',
    'category': 'in:${RecipeCategory.values.map((e) => e.name).join(',')}',
  }, bail: true);

  final updatedRecipe = existingRecipe.copyWith(
    name: data.name ?? existingRecipe.name,
    description: data.description ?? existingRecipe.description,
    ingredients: data.ingredients ?? existingRecipe.ingredients,
    instructions: data.instructions ?? existingRecipe.instructions,
    prepTime: data.prepTime ?? existingRecipe.prepTime,
    cookTime: data.cookTime ?? existingRecipe.cookTime,
    category: data.category != null
        ? RecipeCategory.values.byName(data.category!)
        : existingRecipe.category,
    image: data.image ?? existingRecipe.image,
  );

  final savedRecipe = RecipeService.update(id, updatedRecipe);
  return ctx.json(savedRecipe.toJson());
}
