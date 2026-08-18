import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/models/recipe.dart';
import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

class RecipeBinding implements Bindable {
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

Future<Response> createRecipe(EngineContext ctx) async {
  final data = RecipeBinding();
  await BindingMethods(ctx).bind(data);

  await ValidationContext(ctx).validate({
    'name': 'required|string|min:3',
    'description': 'nullable|string',
    'ingredients': 'required|array',
    'instructions': 'required|string',
    'prepTime': 'required|numeric|min:0',
    'cookTime': 'required|numeric|min:0',
    'category':
        'required|in:${RecipeCategory.values.map((e) => e.name).join(',')}',
  }, bail: true);

  if ((data.cookTime ?? 0) + (data.prepTime ?? 0) > 180) {
    return ctx.string(
      'Total cooking time cannot exceed 3 hours',
      statusCode: HttpStatus.badRequest,
    );
  }

  final recipe = Recipe(
    id: uuid.v4(),
    name: data.name!,
    description: data.description ?? '',
    ingredients: data.ingredients!.map((e) => e.trim()).toList(),
    instructions: data.instructions!,
    prepTime: data.prepTime!,
    cookTime: data.cookTime!,
    category: RecipeCategory.values.byName(data.category!),
    image: data.image ?? '',
  );

  final createdRecipe = RecipeService.create(recipe);
  return ctx.json(createdRecipe.toJson(), statusCode: HttpStatus.created);
}
