import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/models/recipe.dart';
import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

saveRecipe(EngineContext ctx) async {
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
      'category': 'required|in:breakfast,lunch,dinner,dessert'
    });

    final data = await ctx.form();
    oldInput = Map<String, dynamic>.from(data); // Store the input data

    // Convert ingredients string to array after validation
    final ingredients = data['ingredients']
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final recipe = Recipe(
        id: uuid.v4(),
        name: data['name'],
        description: data['description'] ?? '',
        ingredients: ingredients,
        // Use converted array
        instructions: data['instructions'],
        prepTime: int.parse(data['prepTime'].toString()),
        cookTime: int.parse(data['cookTime'].toString()),
        category: RecipeCategory.values.byName(data['category']),
        image: data['image'] ?? '');

    RecipeService.create(recipe);
    await ctx.flash('success', 'Recipe created successfully!');
    await ctx.setSession('errors', {});
    await ctx.setSession('old', {});

    ctx.redirect('/');
  } catch (e) {
    if (e is ValidationError) {
      errors = e.errors; // Store validation errors
      oldInput = await ctx.form();
      await ctx.flash('error', 'Recipe not saved. Please check your input.');
    } else {
      await ctx.flash('error', e.toString());
    }
    await ctx.setSession('errors', errors);
    await ctx.setSession('old', oldInput);
    ctx.redirect('/');
  }
}
