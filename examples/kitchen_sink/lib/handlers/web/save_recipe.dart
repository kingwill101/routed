import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/models/recipe.dart';
import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

Future<Response> saveRecipe(EngineContext ctx) async {
  Map<String, List<String>> errors = {};
  Map<String, dynamic> oldInput = {};

  try {
    await ctx.validate({
      'name': 'required|string|min:3',
      'description': 'string',
      'ingredients': 'required|string', // Changed from array to string
      'instructions': 'required|string',
      'prepTime': 'required|numeric|min:0',
      'cookTime': 'required|numeric|min:0',
      'category': 'required|in:breakfast,lunch,dinner,dessert',
    });

    final data = await ctx.form();
    oldInput = Map<String, dynamic>.from(data);

    // Convert ingredients string to array after validation
    final ingredients = data['ingredients']
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final rawId = (data['id'] ?? '').toString().trim();
    final isUpdate = rawId.isNotEmpty;

    final prepTime = int.tryParse(data['prepTime'].toString()) ?? 0;
    final cookTime = int.tryParse(data['cookTime'].toString()) ?? 0;

    final recipe = Recipe(
      id: isUpdate ? rawId : uuid.v4(),
      name: data['name'],
      description: data['description'] ?? '',
      ingredients: ingredients,
      // Use converted array
      instructions: data['instructions'],
      prepTime: prepTime,
      cookTime: cookTime,
      category: RecipeCategory.values.byName(data['category']),
      image: data['image'] ?? '',
    );

    if (isUpdate) {
      RecipeService.update(recipe.id, recipe);
      ctx.flash('Recipe updated successfully!', 'success');
    } else {
      RecipeService.create(recipe);
      ctx.flash('Recipe created successfully!', 'success');
    }

    ctx.setSession('errors', {});
    ctx.setSession('old', {});

    return ctx.redirect(route('web.recipe.home'));
  } catch (e) {
    if (e is ValidationError) {
      errors = e.errors; // Store validation errors
      ctx.flash('Recipe not saved. Please check your input.', 'error');
    } else {
      ctx.flash(e.toString(), 'error');
    }

    if (oldInput.isEmpty) {
      try {
        final formCopy = await ctx.form();
        oldInput = Map<String, dynamic>.from(formCopy);
      } catch (_) {}
    }

    ctx.setSession('errors', errors);
    ctx.setSession('old', oldInput);
    return ctx.redirect(route('web.recipe.home'));
  }
}
