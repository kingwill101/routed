import 'package:kitchen_sink_example/consts.dart';
import 'package:kitchen_sink_example/services/recipe_service.dart';
import 'package:routed/routed.dart';

Future<Object> uploadImage(EngineContext ctx) async {
  final id = ctx.param('id') ?? '';

  try {
    final recipe = await RecipeService.getById(id);
    if (recipe == null) {
      return ctx.string('Recipe not found', statusCode: HttpStatus.notFound);
    }

    final imageFile = await ctx.formFile('image');

    if (imageFile == null) {
      return ctx.string('No image uploaded', statusCode: HttpStatus.badRequest);
    }
    final imageName = '${uuid.v4()}.${imageFile.filename.split('.').last}';
    final filePath = 'public/images/$imageName';
    await ctx.saveUploadedFile(imageFile, filePath);
    // For simplicity, we'll just store the filename and type.
    await RecipeService.update(
      id,
      recipe.copyWith(image: '/images/$imageName'),
    );
    ctx.removeCache(
      '${kRecipeCacheKeyPrefix}_$id',
      store: 'file',
    ); // Invalidate the recipe cache
    ctx.removeCache(kAllRecipesCacheKey, store: 'file'); // Invalidate the cache
    return await ctx.redirect('/');
  } catch (e) {
    return ctx.string(
      'Error: ${e.toString()}',
      statusCode: HttpStatus.badRequest,
    );
  }
}
